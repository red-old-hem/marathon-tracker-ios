import Foundation
import HealthKit

/// ヘルスケアのランニングワークアウトを読み取り、未チェックの日を自動でチェックインする。
/// 手動記録がある日は種別やメニューを上書きせず、距離と時間だけ補完する。
/// 体重・睡眠・歩数・安静時心拍も読み、体調の auto* 項目にだけ反映する。
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private static let enabledKey = "hk-enabled"
    private static let lastSyncKey = "hk-last-sync"
    private static let lastMessageKey = "hk-last-message"
    private static let lastMessageIsErrorKey = "hk-last-message-is-error"
    /// 体調データの読み取り許可を求めたか。ワークアウトだけで連携済みの端末にも一度だけ尋ねる
    private static let metricsRequestedKey = "hk-metrics-requested"

    private static let metricTypes: Set<HKObjectType> = [
        HKQuantityType(.bodyMass),
        HKQuantityType(.stepCount),
        HKQuantityType(.restingHeartRate),
        HKCategoryType(.sleepAnalysis),
    ]
    private static var readTypes: Set<HKObjectType> { metricTypes.union([HKObjectType.workoutType()]) }

    @Published var isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    @Published private(set) var lastMessage = UserDefaults.standard.string(forKey: lastMessageKey)
    @Published private(set) var lastMessageIsError = UserDefaults.standard.bool(forKey: lastMessageIsErrorKey)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func enable() async -> Bool {
        guard isAvailable else {
            setMessage("この端末ではヘルスケアを利用できません", isError: true)
            return false
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            UserDefaults.standard.set(true, forKey: Self.metricsRequestedKey)
            isEnabled = true
            setMessage("ヘルスケア連携を有効にしました")
            return true
        } catch {
            setMessage("ヘルスケア権限を取得できませんでした: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    func syncWorkouts(into tracker: TrackerStore) async {
        guard !isSyncing else { return }
        guard isAvailable else {
            setMessage("この端末ではヘルスケアを利用できません", isError: true)
            return
        }
        guard isEnabled else { return }

        isSyncing = true
        defer { isSyncing = false }

        // プラン開始前の走り込みも拾えるよう7/1から
        let from = Plan.date(2026, 7, 1)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: from, end: nil, options: []),
        ])

        let workouts: [HKWorkout]
        do {
            workouts = try await fetchWorkouts(predicate: predicate)
        } catch {
            setMessage("ワークアウトを同期できませんでした: \(error.localizedDescription)", isError: true)
            return
        }

        if workouts.isEmpty {
            setSyncResult(workouts: 0, checkedDays: 0, changedDays: 0)
            return
        }

        // 日ごとにグループ化(日をまたぐランは開始日に計上)
        var grouped: [Date: [HKWorkout]] = [:]
        for workout in workouts {
            let day = Plan.calendar.startOfDay(for: workout.startDate)
            grouped[day, default: []].append(workout)
        }

        let summaries = grouped.map { day, list -> WorkoutDaySummary in
            // 丸めは合計してから1回だけ。本ごとに丸めると誤差が積む
            let meters = list.compactMap { $0.totalDistance?.doubleValue(for: .meter()) }
            let km = meters.isEmpty ? nil : ((meters.reduce(0, +) / 1000) * 10).rounded() / 10
            // duration は一時停止分を除いた実走時間なのでペース算出にそのまま使える
            let totalDuration = list.reduce(0.0) { $0 + $1.duration }
            let seconds = totalDuration > 0 ? Int(totalDuration.rounded()) : nil
            return WorkoutDaySummary(date: day, km: km, seconds: seconds,
                                     workoutIDs: list.map { $0.uuid.uuidString })
        }

        let result = tracker.applyWorkouts(summaries)
        setSyncResult(workouts: workouts.count, checkedDays: result.checkedDays, changedDays: result.changedDays)
        if result.changed {
            NotificationManager.reschedule(store: tracker)
        }
    }

    /// ワークアウトと体調をまとめて同期する。アプリ起動・復帰時に呼ぶ
    func syncAll(into tracker: TrackerStore) async {
        await syncWorkouts(into: tracker)
        await syncMetrics(into: tracker)
    }

    /// 直近14日の体重・睡眠・歩数・安静時心拍を日ごとに集計して取り込む。失敗しても画面には出さない(手入力で補える)
    func syncMetrics(into tracker: TrackerStore) async {
        guard isAvailable, isEnabled else { return }
        if !UserDefaults.standard.bool(forKey: Self.metricsRequestedKey) {
            UserDefaults.standard.set(true, forKey: Self.metricsRequestedKey)
            try? await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
        }

        let cal = Plan.calendar
        let end = Date()
        let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: end))!

        async let steps = dailyStatistics(.stepCount, unit: .count(), option: .cumulativeSum, from: start, to: end)
        async let weight = dailyStatistics(.bodyMass, unit: .gramUnit(with: .kilo), option: .mostRecent, from: start, to: end)
        async let heart = dailyStatistics(.restingHeartRate, unit: .count().unitDivided(by: .minute()),
                                          option: .discreteAverage, from: start, to: end)
        async let sleep = dailySleepHours(from: start, to: end)
        let (stepsByDay, weightByDay, heartByDay, sleepByDay) = await (steps, weight, heart, sleep)

        let days = Set(stepsByDay.keys).union(weightByDay.keys).union(heartByDay.keys).union(sleepByDay.keys)
        let summaries = days.map { day in
            HealthDaySummary(
                date: day,
                weightKg: weightByDay[day].map { ($0 * 10).rounded() / 10 },
                sleepHours: sleepByDay[day].map { ($0 * 10).rounded() / 10 },
                steps: stepsByDay[day].map { Int($0.rounded()) },
                restingHR: heartByDay[day].map { Int($0.rounded()) }
            )
        }
        tracker.applyHealthMetrics(summaries)
    }

    private func dailyStatistics(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                                 option: HKStatisticsOptions, from start: Date, to end: Date) async -> [Date: Double] {
        let type = HKQuantityType(identifier)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: option,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: healthStore) else { return [:] }
        var out: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let quantity: HKQuantity?
            switch option {
            case .cumulativeSum: quantity = stats.sumQuantity()
            case .mostRecent: quantity = stats.mostRecentQuantity()
            default: quantity = stats.averageQuantity()
            }
            if let value = quantity?.doubleValue(for: unit), value > 0 {
                out[Plan.calendar.startOfDay(for: stats.startDate)] = value
            }
        }
        return out
    }

    /// 眠っていた区間を、目覚めた日(終了時刻の日)ごとに合計する。
    /// Apple Watch と iPhone の両方が記録すると区間が重なるので、合計の前に重なりをまとめる
    private func dailySleepHours(from start: Date, to end: Date) async -> [Date: Double] {
        let from = Plan.calendar.date(byAdding: .hour, value: -12, to: start)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: from, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: healthStore) else { return [:] }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        var intervals: [Date: [(Date, Date)]] = [:]
        for sample in samples where asleep.contains(sample.value) {
            let day = Plan.calendar.startOfDay(for: sample.endDate)
            guard day >= start else { continue }
            intervals[day, default: []].append((sample.startDate, sample.endDate))
        }
        return intervals.mapValues { Self.mergedHours($0) }.filter { $0.value > 0 }
    }

    /// 区間の和集合の長さ(時間)
    nonisolated static func mergedHours(_ intervals: [(Date, Date)]) -> Double {
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
            if let cur = current, interval.0 <= cur.1 {
                current = (cur.0, max(cur.1, interval.1))
            } else {
                if let cur = current { total += cur.1.timeIntervalSince(cur.0) }
                current = interval
            }
        }
        if let cur = current { total += cur.1.timeIntervalSince(cur.0) }
        return total / 3600
    }

    private func setSyncResult(workouts: Int, checkedDays: Int, changedDays: Int) {
        let now = Date()
        lastSyncAt = now
        UserDefaults.standard.set(now, forKey: Self.lastSyncKey)

        if workouts == 0 {
            setMessage("ランニングワークアウトは見つかりませんでした")
        } else if changedDays == 0 {
            setMessage("同期済みです: ラン\(workouts)件 / \(checkedDays)日")
        } else {
            setMessage("同期しました: ラン\(workouts)件 / \(checkedDays)日中 \(changedDays)日を更新")
        }
    }

    private func setMessage(_ message: String, isError: Bool = false) {
        lastMessage = message
        lastMessageIsError = isError
        UserDefaults.standard.set(message, forKey: Self.lastMessageKey)
        UserDefaults.standard.set(isError, forKey: Self.lastMessageIsErrorKey)
    }

    private func fetchWorkouts(predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples ?? []).compactMap { $0 as? HKWorkout })
                }
            }
            healthStore.execute(query)
        }
    }
}
