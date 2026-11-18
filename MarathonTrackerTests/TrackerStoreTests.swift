import XCTest
@testable import MarathonTracker

@MainActor
final class TrackerStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MarathonTrackerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testWeekIndexUsesCalendarDayBoundaries() {
        XCTAssertEqual(Plan.weekIndex(of: Plan.start), 0)
        XCTAssertEqual(Plan.weekIndex(of: Plan.calendar.date(byAdding: .day, value: 6, to: Plan.start)!), 0)
        XCTAssertEqual(Plan.weekIndex(of: Plan.calendar.date(byAdding: .day, value: 7, to: Plan.start)!), 1)
        XCTAssertEqual(Plan.weekIndex(of: Plan.calendar.date(byAdding: .day, value: -1, to: Plan.start)!), -1)
    }

    func testBackupRoundTripRestoresNextGoalAndLogs() throws {
        let source = TrackerStore(userDefaults: defaults)
        let runDate = Plan.date(2026, 7, 7)
        let goal = NextGoal(name: "神戸マラソン 2027", date: Plan.date(2027, 11, 21), target: "4時間30分")
        source.record(RunLog(type: .run, menu: "イージー40分", km: 6.5), on: runDate)
        source.setNextGoal(goal)

        let backup = try source.exportBackupData()
        let importedDefaults = isolatedDefaults()
        let imported = TrackerStore(userDefaults: importedDefaults)

        XCTAssertEqual(try imported.importBackupData(backup), 1)
        XCTAssertEqual(imported.log(on: runDate)?.km, 6.5)
        XCTAssertEqual(imported.nextGoal, goal)
    }

    func testLegacyBackupStillImportsAndClearsNextGoal() throws {
        let source = TrackerStore(userDefaults: defaults)
        let runDate = Plan.date(2026, 7, 8)
        source.record(RunLog(type: .mini), on: runDate)
        let legacy = try JSONEncoder().encode([source.key(for: runDate): RunLog(type: .mini)])

        let imported = TrackerStore(userDefaults: isolatedDefaults())
        imported.setNextGoal(NextGoal(name: "古い目標", date: Plan.date(2027, 1, 1)))

        XCTAssertEqual(try imported.importBackupData(legacy), 1)
        XCTAssertEqual(imported.log(on: runDate)?.type, .mini)
        XCTAssertNil(imported.nextGoal)
    }

    func testSuggestionAvoidsLowerBodyAfterHighLoad() {
        let store = TrackerStore(userDefaults: defaults)
        let yesterday = Plan.date(2026, 7, 6)
        store.recordStrength(
            StrengthLog(
                category: .lower,
                templateName: "下半身マシン",
                exercises: [StrengthExercise(name: "レッグプレス", reps: 10, sets: 3)],
                rpe: 7
            ),
            on: yesterday
        )

        let suggestion = store.strengthSuggestion(on: Plan.date(2026, 7, 7))

        XCTAssertEqual(suggestion.template?.name, "上半身プッシュ")
    }

    func testSuggestionRecommendsRestForConsecutivePain() {
        let store = TrackerStore(userDefaults: defaults)
        let firstRun = Plan.date(2026, 7, 6)
        let secondRun = Plan.date(2026, 7, 7)
        store.record(RunLog(type: .run, pains: [.knee]), on: firstRun)
        store.record(RunLog(type: .run, pains: [.knee]), on: secondRun)

        let suggestion = store.strengthSuggestion(on: Plan.date(2026, 7, 8))

        XCTAssertNil(suggestion.template)
        XCTAssertEqual(suggestion.title, "今日は筋トレも休養")
    }

    func testStrengthOnlyDayIsHiddenFromRunScreen() {
        let store = makeStore()
        let strengthDay = Plan.date(2026, 11, 16)
        let bothDay = Plan.date(2026, 11, 17)
        store.recordStrength(strength(.upper), on: strengthDay)
        store.record(RunLog(type: .run, km: 5), on: bothDay)
        store.recordStrength(strength(.lower), on: bothDay)

        XCTAssertNil(store.runLog(on: strengthDay))
        XCTAssertEqual(store.runLog(on: bothDay)?.km, 5)
        XCTAssertEqual(store.recentStrengthDays(), [bothDay, strengthDay])
    }

    func testPreviousStrengthUsesOnlyEarlierSavedSession() {
        let store = makeStore()
        let first = Plan.date(2026, 11, 10)
        let second = Plan.date(2026, 11, 12)
        let target = Plan.date(2026, 11, 13)
        store.recordStrength(strength(.upper), on: first)
        store.recordStrength(strength(.lower), on: second)
        store.recordStrength(strength(.core), on: target)

        XCTAssertEqual(store.previousStrength(before: target), strength(.lower))
        XCTAssertEqual(store.previousStrength(before: second), strength(.upper))
        XCTAssertNil(store.previousStrength(before: first))
        let blankDay = Plan.date(2026, 11, 14)
        XCTAssertNotNil(store.previousStrength(before: blankDay))
        XCTAssertNil(store.log(on: blankDay))
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "MarathonTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }
}
