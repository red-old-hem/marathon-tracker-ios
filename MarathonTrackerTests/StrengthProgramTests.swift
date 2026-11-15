import XCTest
@testable import MarathonTracker

/// 12週の筋トレプログラム。2026-11-09 は月曜
@MainActor
final class StrengthProgramTests: XCTestCase {
    private let monday = Plan.date(2026, 11, 9)
    private let wednesday = Plan.date(2026, 11, 11)
    private let saturday = Plan.date(2026, 11, 14)

    // MARK: - 定義

    func testEveryProgramSessionIsAKnownTemplate() {
        XCTAssertEqual(StrengthProgram.weeks.count, 12)
        for (week, plan) in StrengthProgram.weeks.enumerated() {
            XCTAssertTrue(StrengthProgram.phases.indices.contains(plan.phase), "W\(week + 1)")
            for name in plan.sessions {
                XCTAssertNotNil(StrengthProgram.template(named: name, week: week), "W\(week + 1): \(name)")
            }
        }
    }

    func testVolumeFollowsPhase() {
        let intro = StrengthProgram.template(named: "下半身マシン", week: 2)!
        XCTAssertTrue(intro.exercises.allSatisfy { $0.sets == 2 && $0.reps >= 12 })

        let build = StrengthProgram.template(named: "下半身マシン", week: 4)!
        XCTAssertTrue(build.exercises.allSatisfy { $0.sets == 3 })
        XCTAssertEqual(build.exercises.first?.reps, 10)

        let recovery = StrengthProgram.template(named: "全身マシン30分", week: 7)!
        XCTAssertTrue(recovery.exercises.allSatisfy { $0.sets <= 2 })

        XCTAssertEqual(intro.exercises.map(\.name), StrengthTemplate.preset(named: "下半身マシン")!.exercises.map(\.name),
                       "量だけ変えて種目は変えない")
    }

    // MARK: - 開始・週番号

    func testStartAlignsToMondayAndPersists() {
        let defaults = makeIsolatedDefaults()
        let store = TrackerStore(userDefaults: defaults)

        store.startStrengthProgram(on: wednesday)

        XCTAssertEqual(store.key(for: store.strengthProgramStart!), "2026-11-09")
        let reloaded = TrackerStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.key(for: reloaded.strengthProgramStart!), "2026-11-09")
    }

    func testStartOnSundayUsesPreviousMonday() {
        let store = makeStore()
        store.startStrengthProgram(on: Plan.date(2026, 11, 15))
        XCTAssertEqual(store.key(for: store.strengthProgramStart!), "2026-11-09")
    }

    func testStopClearsProgram() {
        let defaults = makeIsolatedDefaults()
        let store = TrackerStore(userDefaults: defaults)
        store.startStrengthProgram(on: monday)

        store.stopStrengthProgram()

        XCTAssertNil(TrackerStore(userDefaults: defaults).strengthProgramStart)
        XCTAssertNil(store.strengthProgramWeek(of: monday))
    }

    func testWeekNumbering() {
        let store = makeStore()
        XCTAssertNil(store.strengthProgramWeek(of: monday), "未開始")

        store.startStrengthProgram(on: monday)

        XCTAssertEqual(store.strengthProgramWeek(of: Plan.date(2026, 11, 15)), 0)
        XCTAssertEqual(store.strengthProgramWeek(of: Plan.date(2026, 11, 16)), 1)
        XCTAssertEqual(store.strengthProgramWeek(of: Plan.date(2026, 11, 8)), -1)
        XCTAssertEqual(store.activeStrengthWeek(of: Plan.date(2027, 1, 31)), 11, "第12週の最終日")
        XCTAssertNil(store.activeStrengthWeek(of: Plan.date(2027, 2, 1)), "終了後")
    }

    // MARK: - 消化状況

    func testDoneCountsMatchTemplateNamesWithinWeek() {
        let store = makeStore()
        store.startStrengthProgram(on: monday)
        store.recordStrength(strength(.full, template: "全身マシン30分"), on: Plan.date(2026, 11, 10))
        store.recordStrength(strength(.core, template: "体幹・安定性マシン"), on: Plan.date(2026, 11, 8)) // 開始前
        store.recordStrength(strength(.upper), on: Plan.date(2026, 11, 12)) // テンプレートなし

        XCTAssertEqual(store.strengthMenuDoneCounts(week: 0), ["全身マシン30分": 1])
        XCTAssertEqual(store.remainingStrengthSessions(week: 0), ["体幹・安定性マシン"])
    }

    func testOffProgramTemplateIsUnchangedPreset() {
        let store = makeStore()
        let preset = StrengthTemplate.preset(named: "下半身マシン")!
        XCTAssertEqual(store.strengthProgramTemplate(named: "下半身マシン", on: monday)?.exercises, preset.exercises)
    }

    // MARK: - サジェスト

    func testSuggestionPicksFirstRemainingSessionWithPhaseVolume() {
        let store = makeStore()
        store.startStrengthProgram(on: monday)

        let suggestion = store.strengthSuggestion(on: wednesday)

        XCTAssertEqual(suggestion.title, "今週のメニューから")
        XCTAssertEqual(suggestion.template?.name, "全身マシン30分")
        XCTAssertTrue(suggestion.template!.exercises.allSatisfy { $0.sets == 2 })
    }

    func testSuggestionSkipsLegSessionsOnLongRunDay() {
        let store = makeStore()
        store.startStrengthProgram(on: monday)

        XCTAssertEqual(store.strengthSuggestion(on: saturday).template?.name, "体幹・安定性マシン")
    }

    func testSuggestionFallsBackToUpperWhenOnlyLegSessionsRemain() {
        let store = makeStore()
        store.startStrengthProgram(on: monday)
        // 第3週: 下半身マシン / 上半身プッシュ
        store.recordStrength(strength(.upper, template: "上半身プッシュ"), on: Plan.date(2026, 11, 23))

        let suggestion = store.strengthSuggestion(on: Plan.date(2026, 11, 28))

        XCTAssertEqual(suggestion.template?.name, "上半身プル")
        XCTAssertTrue(suggestion.reason.contains("脚のメニュー"))
    }

    func testSuggestionWhenWeekIsComplete() {
        let store = makeStore()
        store.startStrengthProgram(on: monday)
        store.recordStrength(strength(.full, template: "全身マシン30分"), on: monday)
        store.recordStrength(strength(.core, template: "体幹・安定性マシン"), on: Plan.date(2026, 11, 10))

        let suggestion = store.strengthSuggestion(on: wednesday)

        XCTAssertNil(suggestion.template)
        XCTAssertEqual(suggestion.title, "今週の筋トレメニューは完了")
    }

    func testPainStreakStillOverridesProgram() {
        let store = makeStore()
        store.startStrengthProgram(on: monday)
        store.record(RunLog(type: .run, pains: [.knee]), on: monday)
        store.record(RunLog(type: .run, pains: [.knee]), on: Plan.date(2026, 11, 10))

        XCTAssertEqual(store.strengthSuggestion(on: wednesday).title, "今日は筋トレも休養")
    }

    // MARK: - バックアップ

    func testBackupRoundTripKeepsProgramStart() throws {
        let source = makeStore()
        source.record(RunLog(type: .run), on: monday)
        source.startStrengthProgram(on: wednesday)

        let imported = makeStore()
        try imported.importBackupData(source.exportBackupData())

        XCTAssertEqual(imported.strengthProgramStart.map(imported.key(for:)), "2026-11-09")
    }

    func testVersion3BackupClearsProgram() throws {
        let json = """
        {"app":"okayama-marathon-18-week-trainer-ios","version":3,"exportedAt":"2026-11-01T00:00:00Z",
         "data":{"logs":{"2026-07-07":{"type":"run"}}}}
        """
        let store = makeStore()
        store.startStrengthProgram(on: monday)

        try store.importBackupData(Data(json.utf8))

        XCTAssertNil(store.strengthProgramStart)
    }

    func testRejectsMalformedProgramStart() {
        let store = makeStore()
        let json = #"{"logs":{"2026-07-07":{"type":"run"}},"strengthProgramStart":"11/09"}"#
        XCTAssertThrowsError(try store.importBackupData(Data(json.utf8)))
    }
}
