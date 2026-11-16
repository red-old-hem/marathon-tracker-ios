import XCTest
@testable import MarathonTracker

/// 日々をつくる(Web版)の書き出しJSONの取り込み
@MainActor
final class HabitLifeImportTests: XCTestCase {

    // Web版の書き出しそのままの形(SQLite由来で数値が文字列、真偽値が bool の列がある)
    private let export = """
    {
      "format": "habit-life-export-v1",
      "exported_at": "2026-11-16T10:00:00.000Z",
      "user": { "email": "user@example.test" },
      "entries": [
        { "id": "e1", "user_id": "u", "happened_on": "2026-11-15", "happened_at": "12:30", "kind": "meal",
          "title": "鮭定食", "meal": "", "groups_json": "[\\"主食\\",\\"肉・魚・卵・豆類\\"]", "note": "",
          "context": "", "amount": "", "unit": "", "minutes": 0, "weight_kg": "", "reps": 0, "sets": 0,
          "photo_key": "photos/x.jpg", "is_favorite": true },
        { "id": "e2", "user_id": "u", "happened_on": "2026-11-15", "happened_at": "18:00", "kind": "exercise",
          "title": "レッグプレス", "groups_json": "[]", "note": "", "amount": "", "unit": "", "minutes": 0,
          "weight_kg": "60", "reps": 10, "sets": 3, "is_favorite": false },
        { "id": "bad", "happened_on": "2026-13-40", "happened_at": "00:00", "kind": "meal", "title": "壊れた日付" }
      ],
      "habits": [
        { "id": "h1", "title": "ストレッチ", "cue": "歯みがきの後", "minimum": "1種目", "archived": false,
          "enforcement_level": "standard", "created_at": "2026-10-01T00:00:00.000Z" }
      ],
      "habit_checks": [
        { "id": "c1", "habit_id": "h1", "checked_on": "2026-11-15", "status": "partial", "detail": "半分" },
        { "id": "c2", "habit_id": "unknown", "checked_on": "2026-11-15", "status": "done", "detail": "" }
      ],
      "daily_metrics": [
        { "id": "m1", "measured_on": "2026-11-15", "weight_kg": "64.5", "sleep_hours": "7", "mood": 0,
          "steps": 8421, "resting_hr": 48 }
      ],
      "work_notes": [
        { "id": "n1", "noted_on": "2026-11-13", "fun": "設計", "drain": "定例" }
      ],
      "weekly_reviews": [
        { "id": "r1", "week_start": "2026-11-09", "wins": "", "lessons": "", "stop_doing": "",
          "next_priority": "提案書" }
      ],
      "work_days": [], "checkups_exams": []
    }
    """.data(using: .utf8)!

    func testImportsEachKindAndConvertsValues() throws {
        let store = makeStore()

        let result = try store.importHabitLife(export)

        XCTAssertEqual(result.entries, 2)
        XCTAssertEqual(result.habits, 1)
        XCTAssertEqual(result.habitChecks, 1)
        XCTAssertEqual(result.metrics, 1)
        XCTAssertEqual(result.workNotes, 1)
        XCTAssertEqual(result.weeklyReviews, 1)
        XCTAssertEqual(result.skipped, 2) // 壊れた日付と、存在しない習慣のチェック

        let meal = try XCTUnwrap(store.dailyEntries["e1"])
        XCTAssertEqual(meal.groups, ["主食", "肉・魚・卵・豆類"])
        XCTAssertTrue(meal.isFavorite)
        XCTAssertEqual(store.dailyEntries["e2"]?.note, "60kg × 10回 × 3セット")
        XCTAssertEqual(store.habits["h1"]?.enforcement, .standard)

        let metric = try XCTUnwrap(store.metrics["2026-11-15"])
        XCTAssertEqual(metric.weightKg, 64.5)
        XCTAssertEqual(metric.sleepHours, 7)
        XCTAssertNil(metric.mood) // Web版の 0 は未入力
        XCTAssertEqual(metric.autoSteps, 8421)
        XCTAssertEqual(store.workNotes["2026-11-13"]?.drain, "定例")
        XCTAssertEqual(store.weeklyReviews["2026-11-09"]?.nextPriority, "提案書")
    }

    func testImportMergesWithoutOverwritingOrTouchingRuns() throws {
        let store = makeStore()
        store.record(RunLog(type: .run, km: 10), on: Plan.date(2026, 11, 15))
        try store.saveWorkNote(fun: "こちらで書いたメモ", drain: "", on: Plan.date(2026, 11, 13))
        try store.importHabitLife(export)

        let again = try store.importHabitLife(export)

        XCTAssertEqual(again.total, 0)
        XCTAssertEqual(store.workNotes["2026-11-13"]?.fun, "こちらで書いたメモ")
        XCTAssertEqual(store.log(on: Plan.date(2026, 11, 15))?.km, 10)
    }

    func testImportsMealsWithoutTitlesAndFillsOnlyMissingMetricFields() throws {
        let store = makeStore()
        let day = Plan.date(2026, 11, 15)
        try store.saveMetric(weightKg: 65, sleepHours: nil, mood: 4, on: day)
        let data = """
        {
          "format": "habit-life-export-v1",
          "entries": [
            { "id": "meal-with-note", "happened_on": "2026-11-15", "happened_at": "12:00",
              "kind": "meal", "title": "", "groups_json": "[]", "note": "サラダ" },
            { "id": "meal-with-photo", "happened_on": "2026-11-15", "happened_at": "18:00",
              "kind": "meal", "title": "", "photo_key": "photos/dinner.jpg" },
            { "id": "meal-with-slot", "happened_on": "2026-11-15", "happened_at": "07:30",
              "kind": "meal", "title": "", "meal": "朝食", "groups_json": "[\\"主食\\"]" }
          ],
          "daily_metrics": [
            { "measured_on": "2026-11-15", "weight_kg": "64.5", "sleep_hours": "7.5",
              "mood": 2, "steps": 8400, "resting_hr": 50 }
          ]
        }
        """.data(using: .utf8)!

        let result = try store.importHabitLife(data)

        XCTAssertEqual(result.entries, 3)
        XCTAssertEqual(result.metrics, 1)
        XCTAssertEqual(store.dailyEntries["meal-with-slot"]?.title, "朝食")
        XCTAssertEqual(store.dailyEntries["meal-with-note"]?.title, "食事（名前なし）")
        XCTAssertEqual(store.dailyEntries["meal-with-note"]?.note, "サラダ")
        XCTAssertEqual(store.dailyEntries["meal-with-photo"]?.title, "食事（名前なし）")
        XCTAssertEqual(store.dailyEntries["meal-with-photo"]?.note, "元の写真は移行されていません")
        XCTAssertEqual(store.metric(on: day)?.weightKg, 65)
        XCTAssertEqual(store.metric(on: day)?.sleepHours, 7.5)
        XCTAssertEqual(store.metric(on: day)?.mood, 4)
        XCTAssertEqual(store.metric(on: day)?.autoSteps, 8400)

        let again = try store.importHabitLife(data)
        XCTAssertEqual(again.total, 0)
    }

    func testRejectsOtherFiles() {
        let store = makeStore()
        let backup = #"{"app":"okayama-marathon-18-week-trainer-ios","version":5,"data":{"logs":{}}}"#

        XCTAssertThrowsError(try store.importHabitLife(Data(backup.utf8)))
    }
}
