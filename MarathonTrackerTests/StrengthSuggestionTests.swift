import XCTest
@testable import MarathonTracker

/// 筋トレサジェストの分岐。2026-07-06 は月曜(プラン初日)
@MainActor
final class StrengthSuggestionTests: XCTestCase {
    private let tuesday = Plan.date(2026, 7, 7)
    private let wednesday = Plan.date(2026, 7, 8)
    private let saturday = Plan.date(2026, 7, 11)

    func testFirstSessionIsLightFullBody() {
        XCTAssertEqual(makeStore().strengthSuggestion(on: wednesday).template?.name, "全身マシン30分")
    }

    func testRunDaysSuggestCore() {
        XCTAssertEqual(makeStore().strengthSuggestion(on: tuesday).template?.name, "体幹・安定性マシン")
        XCTAssertEqual(makeStore().strengthSuggestion(on: Plan.date(2026, 7, 9)).template?.name, "体幹・安定性マシン")
    }

    func testLongRunDayAvoidsLegs() {
        XCTAssertEqual(makeStore().strengthSuggestion(on: saturday).template?.category, .upper)
    }

    func testDemandingRunMenuAvoidsLegs() {
        let store = makeStore()
        store.record(RunLog(type: .run, menu: "ロング走90分"), on: wednesday)

        let suggestion = store.strengthSuggestion(on: wednesday)

        XCTAssertEqual(suggestion.template?.category, .upper)
        XCTAssertTrue(suggestion.reason.contains("ロング走90分"))
    }

    func testLowerBodyPainTodayAvoidsLegs() {
        let store = makeStore()
        store.record(RunLog(type: .run, pains: [.ankle]), on: wednesday)

        XCTAssertEqual(store.strengthSuggestion(on: wednesday).template?.category, .upper)
    }

    func testLegSorenessWithinTwoDaysAvoidsLegs() {
        let store = makeStore()
        store.recordStrength(strength(.full, rpe: 4, soreness: [.glutes]), on: Plan.date(2026, 7, 6))

        XCTAssertEqual(store.strengthSuggestion(on: wednesday).template?.category, .upper)
    }

    func testUpperBodyAlternatesPushAndPull() {
        let store = makeStore()
        store.recordStrength(strength(.upper, template: "上半身プッシュ"), on: Plan.date(2026, 7, 8))

        XCTAssertEqual(store.strengthSuggestion(on: saturday).template?.name, "上半身プル")
    }

    func testAfterUpperBodySuggestsLowerBody() {
        let store = makeStore()
        store.recordStrength(strength(.upper, template: "上半身プル"), on: Plan.date(2026, 7, 6))

        XCTAssertEqual(store.strengthSuggestion(on: wednesday).template?.name, "下半身マシン")
    }

    func testAfterLightLowerBodySplitsToUpper() {
        // 3日以上前の軽い下半身 → 回復判定には掛からないが、部位を分ける
        let store = makeStore()
        store.recordStrength(strength(.lower, rpe: 5), on: Plan.date(2026, 7, 3))

        let suggestion = store.strengthSuggestion(on: wednesday)

        XCTAssertEqual(suggestion.template?.category, .upper)
        XCTAssertTrue(suggestion.reason.contains("下半身"))
    }

    func testFutureSessionsAreIgnoredWhenChoosingByHistory() {
        // 過去日を見返したとき、その日より後の記録を「前回」と扱わない
        let store = makeStore()
        store.recordStrength(strength(.upper), on: Plan.date(2026, 7, 15))

        XCTAssertEqual(store.strengthSuggestion(on: wednesday).template?.name, "全身マシン30分")
    }
}
