import XCTest
@testable import MarathonTracker

/// 次の目標の保存と、JSONバックアップの互換性・検証
@MainActor
final class BackupTests: XCTestCase {

    // MARK: - NextGoal の永続化

    func testNextGoalPersistsAcrossStoreInstances() {
        let defaults = makeIsolatedDefaults()
        let goal = NextGoal(name: "神戸マラソン 2027", date: Plan.date(2027, 11, 21), target: "サブ4.5")

        TrackerStore(userDefaults: defaults).setNextGoal(goal)

        XCTAssertEqual(TrackerStore(userDefaults: defaults).nextGoal, goal)
    }

    func testClearNextGoalRemovesPersistedValue() {
        let defaults = makeIsolatedDefaults()
        let store = TrackerStore(userDefaults: defaults)
        store.setNextGoal(NextGoal(name: "次のレース", date: Plan.date(2027, 3, 1)))

        store.clearNextGoal()

        XCTAssertNil(TrackerStore(userDefaults: defaults).nextGoal)
    }

    func testSettingNextGoalKeepsCompletedRaceLogs() {
        let store = makeStore()
        store.record(RunLog(type: .run, menu: "本番", km: 42.2), on: Plan.race)

        store.setNextGoal(NextGoal(name: "次のレース", date: Plan.date(2027, 3, 1)))

        XCTAssertEqual(store.log(on: Plan.race)?.km, 42.2)
    }

    // MARK: - 旧データ互換

    func testRunLogWithoutNewerFieldsStillDecodes() throws {
        // 初期バージョンの保存形式。後から足した Optional フィールドが無くても読めること
        let json = #"{"type":"run","menu":"イージー40分","km":5}"#.data(using: .utf8)!

        let log = try JSONDecoder().decode(RunLog.self, from: json)

        XCTAssertEqual(log.type, .run)
        XCTAssertEqual(log.km, 5)
        XCTAssertNil(log.strength)
        XCTAssertNil(log.autoKm)
    }

    func testVersion2EnvelopeWithoutNextGoalImports() throws {
        let json = """
        {"app":"okayama-marathon-18-week-trainer-ios","version":2,"exportedAt":"2026-10-01T00:00:00Z",
         "data":{"logs":{"2026-07-07":{"type":"run","km":5}},"suppressedAutoDays":["2026-07-08"]}}
        """.data(using: .utf8)!
        let store = makeStore()

        XCTAssertEqual(try store.importBackupData(json), 1)
        XCTAssertEqual(store.log(on: Plan.date(2026, 7, 7))?.km, 5)
        XCTAssertEqual(store.suppressedAutoDays, ["2026-07-08"])
        XCTAssertNil(store.nextGoal)
    }

    func testLegacyHealthDistanceIsMigratedOnLaunch() throws {
        // 旧sync は km にヘルスケア距離を入れていた。起動時に autoKm へ移す
        let defaults = makeIsolatedDefaults()
        let legacy = ["2026-07-07": RunLog(type: .run, km: 8.4, auto: true)]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "mt-data")

        let log = TrackerStore(userDefaults: defaults).log(on: Plan.date(2026, 7, 7))

        XCTAssertEqual(log?.autoKm, 8.4)
        XCTAssertNil(log?.km)
    }

    // MARK: - 往復

    func testRoundTripKeepsSuppressedDaysAndStrength() throws {
        let source = makeStore()
        let day = Plan.date(2026, 7, 8)
        source.applyWorkouts([WorkoutDaySummary(date: day, km: 5, seconds: 1800, workoutIDs: ["a"])])
        source.remove(on: day) // ヘルスケア由来を取り消す → 抑止リスト入り
        source.recordStrength(strength(.upper, template: "上半身プル", rpe: 6), on: Plan.date(2026, 7, 9))

        let imported = makeStore()
        try imported.importBackupData(source.exportBackupData())

        XCTAssertEqual(imported.suppressedAutoDays, [source.key(for: day)])
        XCTAssertEqual(imported.log(on: Plan.date(2026, 7, 9))?.strength?.templateName, "上半身プル")
    }

    func testImportPreviewDoesNotModifyStore() throws {
        let source = makeStore()
        source.record(RunLog(type: .mini), on: Plan.date(2026, 7, 7))
        source.record(RunLog(type: .run), on: Plan.date(2026, 7, 9))
        let backup = try source.exportBackupData()

        let target = makeStore()
        XCTAssertEqual(try target.importPreviewCount(from: backup), 2)
        XCTAssertTrue(target.logs.isEmpty)
    }

    // MARK: - 検証

    func testRejectsUnknownFormat() {
        assertImportFails("hello", with: { if case .invalidFormat = $0 { return true }; return false })
    }

    func testRejectsEmptyLogs() {
        assertImportFails(#"{"logs":{}}"#, with: { if case .noImportableLogs = $0 { return true }; return false })
    }

    func testRejectsMalformedDateKeys() {
        for key in ["2026-13-01", "2026-7-7", "yesterday"] {
            assertImportFails(#"{"logs":{"\#(key)":{"type":"run"}}}"#, with: {
                if case .invalidDateKey(key) = $0 { return true }; return false
            })
        }
    }

    func testRejectsNegativeDistances() {
        assertImportFails(#"{"logs":{"2026-07-07":{"type":"run","km":-1}}}"#, with: {
            if case .invalidDistance = $0 { return true }; return false
        })
        assertImportFails(#"{"logs":{"2026-07-07":{"type":"run","autoKm":-3}}}"#, with: {
            if case .invalidDistance = $0 { return true }; return false
        })
    }

    func testRejectsInvalidStrength() {
        let outOfRangeRPE = #"{"logs":{"2026-07-07":{"type":"strength","strength":{"category":"upper","exercises":[{"name":"チェストプレス","reps":10,"sets":3}],"rpe":11}}}}"#
        let noExercises = #"{"logs":{"2026-07-07":{"type":"strength","strength":{"category":"upper","exercises":[]}}}}"#
        let blankName = #"{"logs":{"2026-07-07":{"type":"strength","strength":{"category":"upper","exercises":[{"name":"  ","reps":10,"sets":3}]}}}}"#

        for json in [outOfRangeRPE, noExercises, blankName] {
            assertImportFails(json, with: { if case .invalidStrength = $0 { return true }; return false })
        }
    }

    func testRejectsInvalidNextGoal() throws {
        let date = try String(data: JSONEncoder().encode(Plan.date(2027, 3, 1)), encoding: .utf8)!
        let blankName = #"{"logs":{"2026-07-07":{"type":"run"}},"nextGoal":{"name":" ","date":\#(date)}}"#
        let longTarget = #"{"logs":{"2026-07-07":{"type":"run"}},"nextGoal":{"name":"次","date":\#(date),"target":"\#(String(repeating: "あ", count: 81))"}}"#

        for json in [blankName, longTarget] {
            assertImportFails(json, with: { if case .invalidGoal = $0 { return true }; return false })
        }
    }

    func testFailedImportLeavesExistingDataUntouched() {
        let store = makeStore()
        let goal = NextGoal(name: "次のレース", date: Plan.date(2027, 3, 1))
        store.record(RunLog(type: .run, km: 10), on: Plan.date(2026, 7, 7))
        store.setNextGoal(goal)

        XCTAssertThrowsError(try store.importBackupData(Data(#"{"logs":{"2026-07-08":{"type":"run","km":-1}}}"#.utf8)))

        XCTAssertEqual(store.log(on: Plan.date(2026, 7, 7))?.km, 10)
        XCTAssertEqual(store.nextGoal, goal)
    }

    // MARK: - Helpers

    private func assertImportFails(_ json: String,
                                   with matches: (TrackerBackupError) -> Bool,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let store = makeStore()
        XCTAssertThrowsError(try store.importBackupData(Data(json.utf8)), file: file, line: line) { error in
            guard let backupError = error as? TrackerBackupError else {
                return XCTFail("想定外のエラー: \(error)", file: file, line: line)
            }
            XCTAssertTrue(matches(backupError), "想定外のエラー: \(backupError)", file: file, line: line)
        }
    }
}
