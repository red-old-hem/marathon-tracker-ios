import XCTest
@testable import MarathonTracker

/// 日々をつくるから統合した記録(食事・習慣・体調・30秒メモ・週次レビュー)
@MainActor
final class DailyTests: XCTestCase {

    private let monday = Plan.date(2026, 11, 16)

    private func day(_ offset: Int) -> Date {
        Plan.calendar.date(byAdding: .day, value: offset, to: monday)!
    }

    private func meal(_ title: String, day: String = "2026-11-16", time: String = "12:00",
                      favorite: Bool = false) -> DailyEntry {
        DailyEntry(id: TrackerStore.newID(), day: day, time: time, kind: .meal, title: title, isFavorite: favorite)
    }

    // MARK: - 保存

    func testDailyRecordsPersistAcrossStoreInstances() throws {
        let defaults = makeIsolatedDefaults()
        let store = TrackerStore(userDefaults: defaults)
        try store.addEntry(meal("鮭定食"))
        let habit = Habit(id: "h1", title: "ストレッチ")
        try store.saveHabit(habit)
        try store.checkHabit(id: "h1", status: .done, on: monday)
        try store.saveMetric(weightKg: 64.5, sleepHours: nil, mood: 4, on: monday)
        try store.saveWorkNote(fun: "設計", drain: "定例", on: monday)
        try store.saveWeeklyReview(WeeklyReview(weekStart: "2026-11-16", nextPriority: "提案書"))

        let reloaded = TrackerStore(userDefaults: defaults)

        XCTAssertEqual(reloaded.entries(on: monday).map(\.title), ["鮭定食"])
        XCTAssertEqual(reloaded.habitCheck(habitId: "h1", on: monday)?.status, .done)
        XCTAssertEqual(reloaded.metric(on: monday)?.weight, 64.5)
        XCTAssertEqual(reloaded.metric(on: monday)?.mood, 4)
        XCTAssertEqual(reloaded.workNote(on: monday), WorkNote(day: "2026-11-16", fun: "設計", drain: "定例"))
        XCTAssertEqual(reloaded.weeklyReview(weekOf: day(3))?.nextPriority, "提案書")
    }

    func testRunLogsStillLoadWhenDailyDataIsCorrupted() throws {
        // 日々の記録は種類ごとに別キー。壊れていてもラン記録を巻き込まない
        let defaults = makeIsolatedDefaults()
        defaults.set(try JSONEncoder().encode(["2026-07-07": RunLog(type: .run, km: 5)]), forKey: "mt-data")
        defaults.set(Data("not json".utf8), forKey: "mt-daily-entries")

        let store = TrackerStore(userDefaults: defaults)

        XCTAssertEqual(store.log(on: Plan.date(2026, 7, 7))?.km, 5)
        XCTAssertTrue(store.dailyEntries.isEmpty)
    }

    // MARK: - 30秒メモ

    func testWorkNoteNeedsAtLeastOneWord() {
        let store = makeStore()

        XCTAssertThrowsError(try store.saveWorkNote(fun: " ", drain: "", on: monday)) {
            XCTAssertEqual($0 as? DailyInputError, .emptyNote)
        }
        XCTAssertNoThrow(try store.saveWorkNote(fun: "", drain: "電話対応", on: monday))
    }

    // MARK: - 習慣

    func testEnforcementDecidesWhenDetailIsRequired() throws {
        let store = makeStore()
        try store.saveHabit(Habit(id: "gentle", title: "A", enforcement: .gentle))
        try store.saveHabit(Habit(id: "standard", title: "B", enforcement: .standard))
        try store.saveHabit(Habit(id: "strong", title: "C", enforcement: .strong))

        XCTAssertNoThrow(try store.checkHabit(id: "gentle", status: .skip, on: monday))
        XCTAssertNoThrow(try store.checkHabit(id: "standard", status: .done, on: monday))
        XCTAssertThrowsError(try store.checkHabit(id: "standard", status: .partial, on: monday))
        XCTAssertThrowsError(try store.checkHabit(id: "strong", status: .done, on: monday))
        XCTAssertNoThrow(try store.checkHabit(id: "strong", status: .done, detail: "10分", on: monday))
    }

    func testDeletingHabitRemovesItsChecks() throws {
        let store = makeStore()
        try store.saveHabit(Habit(id: "h1", title: "読書"))
        try store.checkHabit(id: "h1", status: .done, on: monday)

        store.deleteHabit(id: "h1")

        XCTAssertTrue(store.habitChecks.isEmpty)
    }

    // MARK: - いつもの

    func testUsualEntriesPutFavoritesFirstThenFrequency() throws {
        let store = makeStore()
        try store.addEntry(meal("納豆ごはん", time: "07:00"))
        try store.addEntry(meal("納豆ごはん", day: "2026-11-15", time: "07:00"))
        try store.addEntry(meal("カレー", time: "12:00"))
        try store.addEntry(meal("プロテイン", day: "2026-11-14", favorite: true))

        XCTAssertEqual(store.usualEntries().map(\.title), ["プロテイン", "納豆ごはん", "カレー"])
    }

    func testRepeatEntryCopiesToTodayWithoutFavorite() throws {
        let store = makeStore()
        let source = meal("プロテイン", day: "2026-11-14", favorite: true)
        try store.addEntry(source)

        let copy = store.repeatEntry(source, at: Plan.calendar.date(bySettingHour: 8, minute: 5, second: 0, of: monday)!)

        XCTAssertEqual(copy.day, "2026-11-16")
        XCTAssertEqual(copy.time, "08:05")
        XCTAssertFalse(copy.isFavorite)
        XCTAssertNotEqual(copy.id, source.id)
    }

    // MARK: - 体調

    func testHealthMetricsNeverOverwriteManualValues() throws {
        let store = makeStore()
        try store.saveMetric(weightKg: 65, sleepHours: nil, mood: nil, on: monday)

        store.applyHealthMetrics([HealthDaySummary(date: monday, weightKg: 64.2, sleepHours: 6.5, steps: 8000)])
        store.applyHealthMetrics([HealthDaySummary(date: monday, steps: 9000)])

        let metric = store.metric(on: monday)
        XCTAssertEqual(metric?.weight, 65)
        XCTAssertEqual(metric?.autoWeightKg, 64.2)
        XCTAssertEqual(metric?.sleep, 6.5)
        XCTAssertEqual(metric?.steps, 9000)
    }

    func testOverlappingSleepIntervalsAreCountedOnce() {
        // Apple Watch と iPhone が同じ睡眠を重ねて記録する場合
        let base = Plan.date(2026, 11, 16)
        let at = { (hour: Double) in base.addingTimeInterval(hour * 3600) }

        let hours = HealthKitManager.mergedHours([(at(0), at(6)), (at(1), at(7)), (at(8), at(9))])

        XCTAssertEqual(hours, 8, accuracy: 0.001)
    }

    // MARK: - 週次集計

    func testWeeklySummaryIncludesRunsAndDailyRecords() throws {
        let store = makeStore()
        store.record(RunLog(type: .run, km: 10), on: day(0))
        store.recordStrength(strength(.lower), on: day(2))
        try store.addEntry(meal("鮭定食", day: "2026-11-17"))
        try store.saveHabit(Habit(id: "h1", title: "読書"))
        try store.checkHabit(id: "h1", status: .small, on: day(1))
        try store.checkHabit(id: "h1", status: .skip, on: day(3))
        store.applyHealthMetrics([HealthDaySummary(date: day(1), sleepHours: 6), HealthDaySummary(date: day(2), sleepHours: 7)])
        try store.saveWorkNote(fun: "設計", drain: "", on: day(4))
        // 翌週の記録は数えない
        store.record(RunLog(type: .run, km: 5), on: day(7))

        let summary = store.weeklySummary(weekOf: day(5))

        XCTAssertEqual(summary.runKm, 10)
        XCTAssertEqual(summary.runCount, 1)
        XCTAssertEqual(summary.strengthCount, 1)
        XCTAssertEqual(summary.meals, 1)
        XCTAssertEqual(summary.habitDone, 1)
        XCTAssertEqual(summary.habitTotal, 2)
        XCTAssertEqual(summary.averageSleep, 6.5)
        XCTAssertEqual(summary.noteDays, 1)
        XCTAssertEqual(summary.activeDays, 4)
    }

    // MARK: - 通知

    func testNoteRemindersOnlyOnWeekdaysWithoutNoteEvenAfterRace() throws {
        let store = makeStore()
        XCTAssertGreaterThan(monday, Plan.race)
        try store.saveWorkNote(fun: "設計", drain: "", on: monday)

        let days = NotificationManager.noteReminderDays(from: monday, store: store).map(store.key(for:))

        XCTAssertEqual(days.count, 9) // 14日のうち平日10日、うち1日は記入済み
        XCTAssertFalse(days.contains("2026-11-16"))
        XCTAssertFalse(days.contains("2026-11-21")) // 土曜
        XCTAssertTrue(days.contains("2026-11-17"))
    }

    // MARK: - バックアップ

    func testVersion5BackupRoundTripsDailyRecords() throws {
        let source = makeStore()
        try source.addEntry(meal("鮭定食"))
        try source.saveHabit(Habit(id: "h1", title: "読書"))
        try source.checkHabit(id: "h1", status: .done, on: monday)
        try source.saveWorkNote(fun: "設計", drain: "定例", on: monday)
        let data = try source.exportBackupData()

        let target = makeStore()
        XCTAssertEqual(try target.importBackupData(data), 4)

        XCTAssertEqual(target.entries(on: monday).map(\.title), ["鮭定食"])
        XCTAssertEqual(target.habitCheck(habitId: "h1", on: monday)?.status, .done)
        XCTAssertEqual(target.workNote(on: monday)?.drain, "定例")
    }

    func testVersion4BackupClearsDailyRecordsOnOverwrite() throws {
        let json = """
        {"app":"okayama-marathon-18-week-trainer-ios","version":4,"exportedAt":"2026-10-01T00:00:00Z",
         "data":{"logs":{"2026-07-07":{"type":"run","km":5}}}}
        """.data(using: .utf8)!
        let store = makeStore()
        try store.saveWorkNote(fun: "設計", drain: "", on: monday)

        XCTAssertEqual(try store.importBackupData(json), 1)

        XCTAssertEqual(store.log(on: Plan.date(2026, 7, 7))?.km, 5)
        XCTAssertTrue(store.workNotes.isEmpty)
    }
}
