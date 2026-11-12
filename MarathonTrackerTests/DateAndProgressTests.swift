import XCTest
@testable import MarathonTracker

/// 日付計算・週集計・継続判定。可変プラン化の前に現行挙動を固定する
@MainActor
final class DateAndProgressTests: XCTestCase {

    // MARK: - 日付

    func testPlanSpansEighteenWeeksEndingOnRaceDay() {
        let store = makeStore()
        XCTAssertEqual(Plan.weeks.count, 18)
        XCTAssertEqual(Plan.weekIndex(of: Plan.race), 17)
        XCTAssertEqual(store.key(for: store.weekDates(17).last!), "2026-11-08")
        XCTAssertEqual(Plan.weekIndex(of: Plan.date(2026, 11, 9)), 18, "レース翌日はプラン終了週")
    }

    func testWeekDatesAreSevenConsecutiveCalendarDays() {
        let store = makeStore()
        for week in 0..<Plan.weeks.count {
            let keys = store.weekDates(week).map(store.key(for:))
            XCTAssertEqual(keys.count, 7)
            XCTAssertEqual(Set(keys).count, 7, "W\(week + 1) に重複日がある: \(keys)")
            for (offset, date) in store.weekDates(week).enumerated() {
                XCTAssertEqual(Plan.weekIndex(of: date), week, "W\(week + 1) の \(offset) 日目")
            }
        }
        // 夏時間などで1日ずれていないこと(週の初日は常に月曜)
        XCTAssertEqual(store.weekDates(0).map(store.key(for:)).first, "2026-07-06")
        XCTAssertEqual(store.weekDates(17).map(store.key(for:)).first, "2026-11-02")
    }

    func testWeekIndexIgnoresTimeOfDay() {
        let lateNight = Plan.calendar.date(byAdding: .minute, value: 23 * 60 + 59, to: Plan.date(2026, 7, 12))!
        XCTAssertEqual(Plan.weekIndex(of: lateNight), 0)
        XCTAssertEqual(Plan.weekIndex(of: Plan.date(2026, 7, 13)), 1)
    }

    // MARK: - 週集計

    func testStrengthOnlyDaysDoNotCountTowardRunGoals() {
        let store = makeStore()
        store.recordStrength(strength(.lower), on: Plan.date(2026, 7, 6))
        store.recordStrength(strength(.upper), on: Plan.date(2026, 7, 7))

        XCTAssertFalse(store.weekAchieved(0))
        XCTAssertEqual(store.weekKm(0), 0)
        XCTAssertEqual(store.totalRuns, 0)
        XCTAssertEqual(store.totalStrengthSessions, 2)
    }

    func testWeekKmPrefersHealthDistanceOverManualEntry() {
        let store = makeStore()
        store.record(RunLog(type: .run, km: 5, autoKm: 6.2), on: Plan.date(2026, 7, 6))
        store.record(RunLog(type: .mini, km: 1), on: Plan.date(2026, 7, 7))

        XCTAssertEqual(store.weekKm(0), 7.2, accuracy: 0.001)
        XCTAssertTrue(store.weekAchieved(0))
    }

    func testStreakToleratesUnfinishedCurrentWeek() {
        let store = makeStore()
        achieve(week: 0, in: store)
        achieve(week: 1, in: store)

        // 第3週はまだ0回でも、進行中なので連続は途切れない
        XCTAssertEqual(store.streak(today: Plan.date(2026, 7, 21)), 2)
    }

    func testStreakBreaksOnMissedPastWeek() {
        let store = makeStore()
        achieve(week: 0, in: store)
        achieve(week: 2, in: store)

        // 第4週(進行中・未達)→ W3達成で1 → W2未達で打ち切り。W1の達成は数えない
        XCTAssertEqual(store.streak(today: Plan.date(2026, 7, 27)), 1)
    }

    func testStreakAfterRaceCountsFinalWeeks() {
        let store = makeStore()
        achieve(week: 16, in: store)
        achieve(week: 17, in: store)

        XCTAssertEqual(store.streak(today: Plan.date(2026, 11, 12)), 2)
        XCTAssertEqual(store.streak(today: Plan.date(2026, 7, 1)), 0, "プラン開始前は0")
    }

    // MARK: - 痛み警告

    func testPainWarningCountsConsecutiveRunsAndSkipsRestDays() {
        let store = makeStore()
        store.record(RunLog(type: .run, pains: [.knee]), on: Plan.date(2026, 7, 6))
        store.record(RunLog(type: .rest), on: Plan.date(2026, 7, 7))
        store.record(RunLog(type: .mini, pains: [.knee, .shin]), on: Plan.date(2026, 7, 8))
        store.record(RunLog(type: .run, pains: [.knee]), on: Plan.date(2026, 7, 9))

        XCTAssertEqual(store.painWarning(), PainWarning(part: .knee, count: 3))
        XCTAssertTrue(store.painWarning()!.severe)
    }

    func testPainWarningClearsAfterPainFreeRun() {
        let store = makeStore()
        store.record(RunLog(type: .run, pains: [.knee]), on: Plan.date(2026, 7, 6))
        store.record(RunLog(type: .run, pains: [.knee]), on: Plan.date(2026, 7, 7))
        store.record(RunLog(type: .run), on: Plan.date(2026, 7, 8))

        XCTAssertNil(store.painWarning())
    }

    // MARK: - Helpers

    private func achieve(week: Int, in store: TrackerStore) {
        let days = store.weekDates(week)
        store.record(RunLog(type: .run), on: days[1])
        store.record(RunLog(type: .run), on: days[3])
    }
}
