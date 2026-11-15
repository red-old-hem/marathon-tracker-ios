import Foundation
import HealthKit

/// ヘルスケアのランニングワークアウトを読み取り、未チェックの日を自動でチェックインする。
/// 手動記録がある日は種別やメニューを上書きせず、距離と時間だけ補完する。
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private static let enabledKey = "hk-enabled"
    private static let lastSyncKey = "hk-last-sync"
    private static let lastMessageKey = "hk-last-message"
    private static let lastMessageIsErrorKey = "hk-last-message-is-error"

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
            try await healthStore.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
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
