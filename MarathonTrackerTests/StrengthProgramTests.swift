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

    func testTemplatesOnlyUseMachinesInTheGym() {
        // テンプレートの種目が、記録画面で選べる設備一覧から外れないようにする
        let machines = Set(StrengthTemplate.machineGroups.flatMap(\.machines))
        for template in StrengthTemplate.presets {
            for exercise in template.exercises {
                XCTAssertTrue(machines.contains(exercise.name), "\(template.name) の \(exercise.name) が設備一覧にない")
            }
        }
    }

    // MARK: - 種目の初期値

    private func logMachine(_ name: String, weight: Double, reps: Int, sets: Int, on date: Date, in store: TrackerStore) {
        store.recordStrength(StrengthLog(category: .upper,
                                         exercises: [StrengthExercise(name: name, weightKg: weight, reps: reps, sets: sets)]),
                             on: date)
    }

    func testAddedMachineCarriesOverLastSession() {
        let store = makeStore()
        logMachine("チェストプレス", weight: 30, reps: 8, sets: 3, on: Plan.date(2026, 11, 2), in: store)
        logMachine("チェストプレス", weight: 32.5, reps: 10, sets: 3, on: Plan.date(2026, 11, 9), in: store)
        // 同じ日や後の日の記録は前回として使わない
        logMachine("チェストプレス", weight: 99, reps: 1, sets: 1, on: Plan.date(2026, 11, 16), in: store)

        let suggested = store.suggestedExercise(named: "チェストプレス", on: Plan.date(2026, 11, 16))

        XCTAssertEqual(suggested, StrengthExercise(name: "チェストプレス", weightKg: 32.5, reps: 10, sets: 3))
        XCTAssertEqual(store.suggestedExercise(named: "レッグプレス", on: Plan.date(2026, 11, 16)),
                       StrengthExercise(name: "レッグプレス", reps: 10, sets: 3))
    }

    func testAddedMachineFollowsProgramVolume() {
        let store = makeStore()
        let start = Plan.date(2026, 11, 16)
        store.startStrengthProgram(on: start)
        logMachine("チェストプレス", weight: 40, reps: 10, sets: 3, on: Plan.date(2026, 11, 9), in: store)

        // 第1週は導入期: 12回以上×2セット、重量は前回のまま
        XCTAssertEqual(store.suggestedExercise(named: "チェストプレス", on: start),
                       StrengthExercise(name: "チェストプレス", weightKg: 40, reps: 12, sets: 2))
        // 第8週は回復週: 2セット、重量を2割下げる
        let recovery = Plan.calendar.date(byAdding: .day, value: 7 * 7, to: start)!
        XCTAssertEqual(store.suggestedExercise(named: "チェストプレス", on: recovery),
                       StrengthExercise(name: "チェストプレス", weightKg: 32, reps: 10, sets: 2))
    }

    func testChosenRecommendedExercisesStayDraftUntilSavedAndMergeWithoutOverwriting() {
        let store = makeStore()
        let day = Plan.date(2026, 11, 16)
        let existing = StrengthLog(category: .upper, exercises: [
            StrengthExercise(name: "チェストプレス", weightKg: 42.5, reps: 8, sets: 3)
        ], rpe: 7)
        store.recordStrength(existing, on: day)
        let selected = StrengthLog(category: .upper, templateName: "上半身プッシュ", exercises: [
            StrengthExercise(name: "チェストプレス", weightKg: 40, reps: 10, sets: 3),
            StrengthExercise(name: "ペクトルフライ", weightKg: 20, reps: 12, sets: 2)
        ])
        let draft = existing.addingRecommendedExercises(selected)

        XCTAssertEqual(store.log(on: day)?.strength, existing)
        XCTAssertEqual(draft.exercises.count, 2)
        XCTAssertEqual(draft.exercises[0].weightKg, 42.5)
        XCTAssertEqual(draft.exercises[1].name, "ペクトルフライ")
        XCTAssertEqual(draft.rpe, 7)
        XCTAssertEqual(draft.templateName, "上半身プッシュ")
        let partial = StrengthLog(category: .upper, exercises: [selected.exercises[0]])
        XCTAssertNil(existing.addingRecommendedExercises(partial).templateName)
    }

    func testPreparedWeeklyMenuShowsMachinesAndLastWeights() {
        let store = makeStore()
        let start = Plan.date(2026, 11, 16)
        store.startStrengthProgram(on: start)
        logMachine("チェストプレス", weight: 40, reps: 10, sets: 3,
                   on: Plan.date(2026, 11, 9), in: store)

        let menu = store.preparedStrengthTemplate(named: "全身マシン30分", on: start)!
        XCTAssertEqual(menu.exercises.map(\.name),
                       ["レッグプレス", "チェストプレス", "ラットプルダウン", "ケーブル・クランチ"])
        XCTAssertEqual(menu.exercises[1].weightKg, 40)
        XCTAssertEqual(menu.exercises[1].reps, 12)
        XCTAssertEqual(menu.exercises[1].sets, 2)
        XCTAssertNil(menu.exercises[0].weightKg)
    }

    func testTemplateExercisesGetLastWeight() {
        let store = makeStore()
        logMachine("レッグプレス", weight: 80, reps: 10, sets: 3, on: Plan.date(2026, 11, 9), in: store)
        let template = StrengthExercise(name: "レッグプレス", reps: 10, sets: 2)

        XCTAssertEqual(store.withLastWeight(template, on: Plan.date(2026, 11, 16)).weightKg, 80)
        XCTAssertEqual(store.withLastWeight(StrengthExercise(name: "レッグプレス", weightKg: 60, reps: 10, sets: 2),
                                            on: Plan.date(2026, 11, 16)).weightKg, 60)
    }
}
