import XCTest
@testable import MarathonTracker

/// 次の目標(フルマラソン)に向けたプラン。週番号は岡山の開始日からの通し番号(レース後は18以上)
@MainActor
final class GoalPlanTests: XCTestCase {
    /// レース後3週目の月曜
    private let today = Plan.date(2026, 11, 23)

    // MARK: - 期間の決め方

    func testLongLeadTimeUsesFullEighteenWeeksEndingOnRaceWeek() {
        let store = makeStore()
        let race = Plan.date(2027, 6, 27)
        store.setNextGoal(NextGoal(name: "春のフル", date: race, planStart: today))

        let plan = store.goalPlan!

        XCTAssertEqual(plan.count, 18)
        XCTAssertEqual(plan.raceWeek, store.weekIndex(of: race))
        XCTAssertEqual(plan.startWeek, plan.raceWeek - 17)
        XCTAssertFalse(plan.isShortened)
        XCTAssertEqual(plan.week(at: plan.raceWeek)?.runs.last, "本番 42.195km!")
        XCTAssertNil(plan.week(at: plan.startWeek - 1))
    }

    func testShortLeadTimeUsesSecondHalfOfOkayamaPlan() {
        let store = makeStore()
        let startWeek = store.weekIndex(of: today)
        let race = store.weekDates(startWeek + 9).last! // 10週目の日曜
        store.setNextGoal(NextGoal(name: "冬のフル", date: race, planStart: today))

        let plan = store.goalPlan!

        XCTAssertEqual(plan.count, 10)
        XCTAssertEqual(plan.startWeek, startWeek)
        XCTAssertEqual(plan.templateOffset, 8)
        XCTAssertEqual(plan.firstWeek.runs, Plan.weeks[8].runs, "岡山の第9週から")
        XCTAssertEqual(plan.number(of: startWeek), 1)
        XCTAssertEqual(plan.number(of: plan.raceWeek), 10)
    }

    func testSaturdayRaceStaysInItsWeek() {
        let store = makeStore()
        let week = store.weekIndex(of: today) + 5
        let saturday = store.weekDates(week)[5]
        store.setNextGoal(NextGoal(name: "土曜開催", date: saturday, planStart: today))

        XCTAssertEqual(store.goalPlan?.raceWeek, week)
    }

    func testLegacyGoalWithoutPlanStartStartsNoEarlierThanWeekAfterRace() {
        let store = makeStore()
        let race = store.weekDates(Plan.weeks.count + 5).last!
        store.setNextGoal(NextGoal(name: "旧データ", date: race))

        XCTAssertEqual(store.goalPlan?.startWeek, Plan.weeks.count, "レース翌週(第19週)より前には始めない")
        XCTAssertEqual(store.goalPlan?.count, 6)
    }

    func testPlanStartTooEarlyIsClampedToEighteenWeeks() {
        let store = makeStore()
        let race = Plan.date(2027, 9, 26)
        store.setNextGoal(NextGoal(name: "秋のフル", date: race, planStart: today))

        XCTAssertEqual(store.goalPlan?.count, 18, "開始が早すぎても18週を超えない")
    }

    func testNoGoalMeansNoPlanAfterRace() {
        let store = makeStore()
        XCTAssertNil(store.goalPlan)
        XCTAssertNil(store.weekPlan(of: Plan.weeks.count + 2))
        XCTAssertEqual(store.weekPlan(of: 5)?.runs, Plan.weeks[5].runs, "岡山の週は今までどおり")
    }

    // MARK: - メニュー

    func testMenusFollowGoalPlanOnlyInsidePlanWeeks() {
        let store = makeStore()
        let startWeek = store.weekIndex(of: today) + 2
        let race = store.weekDates(startWeek + 9).last!
        store.setNextGoal(NextGoal(name: "冬のフル", date: race, planStart: store.weekDates(startWeek)[0]))
        let firstDay = store.weekDates(startWeek)[1]

        XCTAssertEqual(store.nextMenu(on: firstDay), Plan.weeks[8].runs[0])
        XCTAssertEqual(store.menuOptions(on: firstDay), Plan.weeks[8].runs + ["メニュー外の自由ラン"])
        XCTAssertEqual(store.defaultMenu(on: firstDay), Plan.weeks[8].runs[0])

        // プラン開始前のレース後の週は自由ランのまま
        XCTAssertEqual(store.menuOptions(on: today), Plan.freeMenus)
        XCTAssertEqual(store.defaultMenu(on: today), Plan.freeMenus[0])
        XCTAssertNil(store.nextMenu(on: today))

        // 岡山の日付は岡山のメニュー
        XCTAssertEqual(store.nextMenu(on: Plan.date(2026, 7, 7)), "イージー40分")
    }

    func testDoneMenusAdvanceWithinGoalWeek() {
        let store = makeStore()
        let startWeek = store.weekIndex(of: today)
        store.setNextGoal(NextGoal(name: "冬のフル", date: store.weekDates(startWeek + 9).last!, planStart: today))
        let runs = Plan.weeks[8].runs

        store.record(RunLog(type: .run, menu: runs[0], km: 8), on: store.weekDates(startWeek)[1])

        XCTAssertEqual(store.menuDoneCounts(week: startWeek), [runs[0]: 1])
        XCTAssertEqual(store.nextMenu(on: store.weekDates(startWeek)[3]), runs[1])
        XCTAssertEqual(store.stat(week: startWeek).targetKm, Plan.weeks[8].km)
    }

    func testHealthSyncAssignsGoalMenuOnlyInPlanWeeks() {
        let store = makeStore()
        let startWeek = store.weekIndex(of: today) + 1
        store.setNextGoal(NextGoal(name: "冬のフル", date: store.weekDates(startWeek + 9).last!,
                                   planStart: store.weekDates(startWeek)[0]))
        let inPlan = store.weekDates(startWeek)[2]

        store.applyWorkouts([
            WorkoutDaySummary(date: today, km: 5, seconds: 1800, workoutIDs: ["a"]),
            WorkoutDaySummary(date: inPlan, km: 6, seconds: 2100, workoutIDs: ["b"]),
        ])

        XCTAssertNil(store.log(on: today)?.menu, "プラン開始前はメニューを付けない")
        XCTAssertEqual(store.log(on: inPlan)?.menu, Plan.weeks[8].runs[0])
    }

    // MARK: - 保存時の開始週

    func testPlanStartIsKeptWhenRaceDateIsUnchanged() {
        let store = makeStore()
        let race = Plan.date(2027, 3, 7)
        store.setNextGoal(NextGoal(name: "春のフル", date: race, planStart: Plan.date(2026, 11, 16)))

        XCTAssertEqual(store.key(for: store.planStartForGoal(date: race, today: today)), "2026-11-16")
        XCTAssertEqual(store.key(for: store.planStartForGoal(date: Plan.date(2027, 3, 14), today: Plan.date(2026, 11, 26))),
                       "2026-11-23", "開催日を変えたら今週の月曜から")
    }

    // MARK: - 注意表示

    func testWarningForShortPlanWithLowRecentVolume() {
        let store = makeStore()
        let startWeek = store.weekIndex(of: today)
        store.setNextGoal(NextGoal(name: "冬のフル", date: store.weekDates(startWeek + 9).last!, planStart: today))

        let warning = store.goalPlanWarning(today: today)

        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.contains("第9週から"))
    }

    func testNoWarningWhenRecentVolumeIsEnough() {
        let store = makeStore()
        let startWeek = store.weekIndex(of: today)
        store.setNextGoal(NextGoal(name: "冬のフル", date: store.weekDates(startWeek + 9).last!, planStart: today))
        for offset in [3, 10, 17, 24] {
            store.record(RunLog(type: .run, km: 20), on: Plan.calendar.date(byAdding: .day, value: -offset, to: today)!)
        }

        XCTAssertNil(store.goalPlanWarning(today: today))
    }

    func testNoWarningForFullPlanOrLaterWeeks() {
        let full = makeStore()
        full.setNextGoal(NextGoal(name: "春のフル", date: Plan.date(2027, 6, 27), planStart: today))
        XCTAssertNil(full.goalPlanWarning(today: today))

        let short = makeStore()
        let startWeek = short.weekIndex(of: today)
        short.setNextGoal(NextGoal(name: "冬のフル", date: short.weekDates(startWeek + 9).last!, planStart: today))
        XCTAssertNil(short.goalPlanWarning(today: short.weekDates(startWeek + 2)[0]), "3週目以降は出さない")
    }

    // MARK: - バックアップ

    func testBackupRoundTripKeepsPlanStart() throws {
        let source = makeStore()
        source.record(RunLog(type: .run), on: today)
        source.setNextGoal(NextGoal(name: "春のフル", date: Plan.date(2027, 3, 7), planStart: Plan.date(2026, 11, 16)))

        let imported = makeStore()
        try imported.importBackupData(source.exportBackupData())

        XCTAssertEqual(imported.nextGoal?.planStart.map(imported.key(for:)), "2026-11-16")
        XCTAssertEqual(imported.goalPlan, source.goalPlan)
    }

    func testRejectsPlanStartAfterRace() throws {
        let source = makeStore()
        source.record(RunLog(type: .run), on: today)
        source.setNextGoal(NextGoal(name: "おかしな目標", date: Plan.date(2027, 3, 7), planStart: Plan.date(2027, 4, 1)))

        XCTAssertThrowsError(try makeStore().importBackupData(source.exportBackupData())) { error in
            guard case .invalidGoal = error as? TrackerBackupError else {
                return XCTFail("想定外のエラー: \(error)")
            }
        }
    }
}
