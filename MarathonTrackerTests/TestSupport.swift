import XCTest
@testable import MarathonTracker

extension XCTestCase {
    /// 実機の UserDefaults.standard を汚さないよう、テストごとに使い捨てのスイートを作る
    func makeIsolatedDefaults() -> UserDefaults {
        let name = "MarathonTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    @MainActor
    func makeStore() -> TrackerStore {
        TrackerStore(userDefaults: makeIsolatedDefaults())
    }

    func strength(_ category: StrengthCategory,
                  template: String? = nil,
                  rpe: Int? = nil,
                  soreness: [SorenessArea]? = nil) -> StrengthLog {
        StrengthLog(
            category: category,
            templateName: template,
            exercises: [StrengthExercise(name: "テスト種目", reps: 10, sets: 3)],
            rpe: rpe,
            soreness: soreness
        )
    }
}
