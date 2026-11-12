import XCTest
@testable import MarathonTracker

/// ヘルスケア取り込み(applyWorkouts)と、記録の削除まわり
@MainActor
final class HealthSyncTests: XCTestCase {
    private let monday = Plan.date(2026, 7, 6)
    private let tuesday = Plan.date(2026, 7, 7)
    private let wednesday = Plan.date(2026, 7, 8)

    func testNewDaysGetDistinctMenusWithinOneBatch() {
        let store = makeStore()

        store.applyWorkouts([
            WorkoutDaySummary(date: monday, km: 5, seconds: 2400, workoutIDs: ["a"]),
            WorkoutDaySummary(date: tuesday, km: 5, seconds: 2400, workoutIDs: ["b"]),
            WorkoutDaySummary(date: wednesday, km: 7, seconds: 3000, workoutIDs: ["c"]),
        ])

        XCTAssertEqual(store.log(on: monday)?.menu, "イージー40分")
        XCTAssertEqual(store.log(on: tuesday)?.menu, "イージー40分")
        XCTAssertEqual(store.log(on: wednesday)?.menu, "イージー50分")
        XCTAssertEqual(store.log(on: monday)?.auto, true)
    }

    func testApplyingSameWorkoutsTwiceIsIdempotent() {
        let store = makeStore()
        let summaries = [WorkoutDaySummary(date: monday, km: 5, seconds: 2400, workoutIDs: ["b", "a"])]

        XCTAssertEqual(store.applyWorkouts(summaries).changedDays, 1)
        let second = store.applyWorkouts(summaries)

        XCTAssertEqual(second.checkedDays, 1)
        XCTAssertEqual(second.changedDays, 0)
        XCTAssertEqual(store.log(on: monday)?.workoutIDs, ["a", "b"])
    }

    func testSyncNeverRewritesManualEntries() {
        let store = makeStore()
        store.record(RunLog(type: .mini, km: 1, pains: [.knee], feel: .heavy), on: monday)

        store.applyWorkouts([WorkoutDaySummary(date: monday, km: 2.1, seconds: 900, workoutIDs: ["a"])])

        let log = store.log(on: monday)
        XCTAssertEqual(log?.type, .mini, "5分だけ を走ったに昇格させない")
        XCTAssertEqual(log?.km, 1)
        XCTAssertEqual(log?.pains, [.knee])
        XCTAssertEqual(log?.feel, .heavy)
        XCTAssertEqual(log?.autoKm, 2.1)
        XCTAssertEqual(log?.distanceKm, 2.1)
    }

    func testWorkoutWithoutDistanceKeepsPreviousAutoKm() {
        let store = makeStore()
        store.applyWorkouts([WorkoutDaySummary(date: monday, km: 6, seconds: 2400, workoutIDs: ["a"])])

        store.applyWorkouts([WorkoutDaySummary(date: monday, km: nil, seconds: 3000, workoutIDs: ["a", "b"])])

        XCTAssertEqual(store.log(on: monday)?.autoKm, 6)
        XCTAssertEqual(store.log(on: monday)?.autoSeconds, 3000)
    }

    func testRemovedHealthDayIsNotRestoredBySync() {
        let store = makeStore()
        let summaries = [WorkoutDaySummary(date: monday, km: 5, seconds: 2400, workoutIDs: ["a"])]
        store.applyWorkouts(summaries)

        store.remove(on: monday)
        let result = store.applyWorkouts(summaries)

        XCTAssertNil(store.log(on: monday))
        XCTAssertEqual(result.checkedDays, 0)
    }

    func testManualRecordLiftsSuppression() {
        let store = makeStore()
        store.applyWorkouts([WorkoutDaySummary(date: monday, km: 5, seconds: 2400, workoutIDs: ["a"])])
        store.remove(on: monday)

        store.record(RunLog(type: .run), on: monday)

        XCTAssertFalse(store.suppressedAutoDays.contains(store.key(for: monday)))
    }

    func testStrengthOnlyDayIsPromotedToRunAndKeepsStrength() {
        let store = makeStore()
        store.recordStrength(strength(.upper), on: monday)

        store.applyWorkouts([WorkoutDaySummary(date: monday, km: 5, seconds: 2400, workoutIDs: ["a"])])

        let log = store.log(on: monday)
        XCTAssertEqual(log?.type, .run)
        XCTAssertEqual(log?.menu, "イージー40分")
        XCTAssertEqual(log?.strength?.category, .upper)
    }

    // MARK: - 削除

    func testRemovingRunKeepsSameDayStrength() {
        let store = makeStore()
        store.record(RunLog(type: .run, km: 5), on: monday)
        store.recordStrength(strength(.core), on: monday)

        store.removeRunRecord(on: monday)

        XCTAssertEqual(store.log(on: monday)?.type, .strength)
        XCTAssertNil(store.log(on: monday)?.km)
        XCTAssertEqual(store.log(on: monday)?.strength?.category, .core)
    }

    func testRemovingStrengthKeepsSameDayRun() {
        let store = makeStore()
        store.record(RunLog(type: .run, km: 5), on: monday)
        store.recordStrength(strength(.core), on: monday)

        store.removeStrength(on: monday)

        XCTAssertEqual(store.log(on: monday)?.km, 5)
        XCTAssertNil(store.log(on: monday)?.strength)
    }

    func testRemovingStrengthOnlyDayDeletesLog() {
        let store = makeStore()
        store.recordStrength(strength(.core), on: monday)

        store.removeStrength(on: monday)

        XCTAssertNil(store.log(on: monday))
    }
}
