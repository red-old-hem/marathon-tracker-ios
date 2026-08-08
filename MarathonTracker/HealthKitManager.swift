import Foundation
import HealthKit

/// ヘルスケアのランニングワークアウトを読み取り、未チェックの日を自動でチェックインする。
/// 手動記録がある日はスキップし、上書きしない。
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private static let enabledKey = "hk-enabled"

    @Published var isEnabled = UserDefaults.standard.bool(forKey: enabledKey)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func enable() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            isEnabled = true
            return true
        } catch {
            return false
        }
    }

    func syncWorkouts(into tracker: TrackerStore) async {
        guard isEnabled, isAvailable else { return }

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
            return
        }

        guard !workouts.isEmpty else { return }

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

        if tracker.applyWorkouts(summaries) {
            NotificationManager.reschedule(store: tracker)
        }
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
