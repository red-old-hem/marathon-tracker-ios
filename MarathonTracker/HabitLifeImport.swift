import Foundation

/// 「日々をつくる」(Web版)の書き出しJSON(format: habit-life-export-v1)を読み込み、日々の記録へ追加する。
/// 上書きではなくマージ。同じIDや同じ日付の記録がすでにあれば、こちらの記録を残して読み飛ばす。
/// ラン記録・筋トレ・目標には触れない。
struct HabitLifeImportResult: Equatable {
    var entries = 0
    var habits = 0
    var habitChecks = 0
    var metrics = 0
    var workNotes = 0
    var weeklyReviews = 0
    var skipped = 0

    var total: Int { entries + habits + habitChecks + metrics + workNotes + weeklyReviews }

    var summary: String {
        var parts: [String] = []
        if entries > 0 { parts.append("食事・サプリ\(entries)件") }
        if habits > 0 { parts.append("習慣\(habits)件") }
        if habitChecks > 0 { parts.append("習慣チェック\(habitChecks)件") }
        if metrics > 0 { parts.append("体調\(metrics)日") }
        if workNotes > 0 { parts.append("30秒メモ\(workNotes)日") }
        if weeklyReviews > 0 { parts.append("週の振り返り\(weeklyReviews)件") }
        let added = parts.isEmpty ? "新しく取り込む記録はありませんでした" : parts.joined(separator: "、") + "を取り込みました"
        return skipped > 0 ? "\(added)(既にある\(skipped)件はそのまま)" : added
    }
}

enum HabitLifeImportError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        "日々をつくるの書き出しファイル(habit-life-export-v1)ではありません"
    }
}

extension TrackerStore {
    static let habitLifeFormat = "habit-life-export-v1"

    @discardableResult
    func importHabitLife(_ data: Data) throws -> HabitLifeImportResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == Self.habitLifeFormat else {
            throw HabitLifeImportError.invalidFormat
        }
        let rows = { (name: String) in (root[name] as? [[String: Any]]) ?? [] }
        var result = HabitLifeImportResult()

        // 1件ずつ代入すると didSet のたびに全件保存されるので、コピーに足してから一度だけ戻す
        var nextEntries = dailyEntries
        for row in rows("entries") {
            guard let entry = Self.entry(from: row), dailyDate(entry.day) != nil else { result.skipped += 1; continue }
            if nextEntries[entry.id] != nil { result.skipped += 1; continue }
            nextEntries[entry.id] = entry
            result.entries += 1
        }

        var nextHabits = habits
        for row in rows("habits") {
            guard let id = Self.string(row["id"]), let title = Self.string(row["title"]), !title.isEmpty else {
                result.skipped += 1; continue
            }
            if nextHabits[id] != nil { result.skipped += 1; continue }
            nextHabits[id] = Habit(
                id: id,
                title: title,
                cue: Self.string(row["cue"]) ?? "",
                minimum: Self.string(row["minimum"]) ?? "",
                enforcement: Self.string(row["enforcement_level"]).flatMap(HabitEnforcement.init(rawValue:)) ?? .gentle,
                archived: Self.bool(row["archived"]),
                createdAt: Self.string(row["created_at"]) ?? ""
            )
            result.habits += 1
        }

        var nextChecks = habitChecks
        for row in rows("habit_checks") {
            guard let habitId = Self.string(row["habit_id"]), nextHabits[habitId] != nil,
                  let day = Self.string(row["checked_on"]), dailyDate(day) != nil,
                  let status = Self.string(row["status"]).flatMap(HabitStatus.init(rawValue:)) else {
                result.skipped += 1; continue
            }
            let check = HabitCheck(habitId: habitId, day: day, status: status, detail: Self.string(row["detail"]) ?? "")
            if nextChecks[check.storageKey] != nil { result.skipped += 1; continue }
            nextChecks[check.storageKey] = check
            result.habitChecks += 1
        }

        var nextMetrics = metrics
        for row in rows("daily_metrics") {
            guard let day = Self.string(row["measured_on"]), dailyDate(day) != nil else { result.skipped += 1; continue }
            // 項目ごとに既存値を優先し、空欄だけWeb版から埋める
            var metric = nextMetrics[day] ?? DailyMetric(day: day)
            let before = metric
            metric.weightKg = metric.weightKg ?? Self.double(row["weight_kg"]).flatMap { (20...400).contains($0) ? $0 : nil }
            metric.sleepHours = metric.sleepHours ?? Self.double(row["sleep_hours"]).flatMap { (0.1...24).contains($0) ? $0 : nil }
            metric.mood = metric.mood ?? Self.int(row["mood"]).flatMap { (1...5).contains($0) ? $0 : nil }
            // Web版の歩数・心拍は iPhone のショートカットから入ったヘルスケアの値
            metric.autoSteps = metric.autoSteps ?? Self.int(row["steps"]).flatMap { $0 > 0 ? $0 : nil }
            metric.autoRestingHR = metric.autoRestingHR ?? Self.int(row["resting_hr"]).flatMap { $0 > 0 ? $0 : nil }
            guard metric != before, !metric.isEmpty else { result.skipped += 1; continue }
            nextMetrics[day] = metric
            result.metrics += 1
        }

        var nextNotes = workNotes
        for row in rows("work_notes") {
            guard let day = Self.string(row["noted_on"]), dailyDate(day) != nil else { result.skipped += 1; continue }
            let fun = Self.string(row["fun"]) ?? ""
            let drain = Self.string(row["drain"]) ?? ""
            if nextNotes[day] != nil || (fun.isEmpty && drain.isEmpty) { result.skipped += 1; continue }
            nextNotes[day] = WorkNote(day: day, fun: fun, drain: drain)
            result.workNotes += 1
        }

        var nextReviews = weeklyReviews
        for row in rows("weekly_reviews") {
            guard let week = Self.string(row["week_start"]), dailyDate(week) != nil else { result.skipped += 1; continue }
            let review = WeeklyReview(
                weekStart: week,
                wins: Self.string(row["wins"]) ?? "",
                lessons: Self.string(row["lessons"]) ?? "",
                stopDoing: Self.string(row["stop_doing"]) ?? "",
                nextPriority: Self.string(row["next_priority"]) ?? ""
            )
            if nextReviews[week] != nil || review.isEmpty { result.skipped += 1; continue }
            nextReviews[week] = review
            result.weeklyReviews += 1
        }

        if result.entries > 0 { dailyEntries = nextEntries }
        if result.habits > 0 { habits = nextHabits }
        if result.habitChecks > 0 { habitChecks = nextChecks }
        if result.metrics > 0 { metrics = nextMetrics }
        if result.workNotes > 0 { workNotes = nextNotes }
        if result.weeklyReviews > 0 { weeklyReviews = nextReviews }
        return result
    }

    private static func entry(from row: [String: Any]) -> DailyEntry? {
        guard let id = string(row["id"]),
              let day = string(row["happened_on"]),
              let kind = string(row["kind"]).flatMap(EntryKind.init(rawValue:)) else { return nil }
        let originalTitle = string(row["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard kind == .meal || !originalTitle.isEmpty else { return nil }
        // 名前が空の食事は、Web版の区分(朝食・昼食など)があればそれを名前にする
        let slot = string(row["meal"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = !originalTitle.isEmpty ? originalTitle : (slot.isEmpty ? "食事（名前なし）" : slot)
        let groups = string(row["groups_json"])
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String] } ?? []
        var notes = [string(row["note"]) ?? ""]
        if let photoKey = string(row["photo_key"]), !photoKey.isEmpty {
            notes.append("元の写真は移行されていません")
        }
        // 筋トレの重量・回数はここでは列を持たないので、メモに残す
        let weight = string(row["weight_kg"]) ?? ""
        let reps = int(row["reps"]) ?? 0
        let sets = int(row["sets"]) ?? 0
        if reps > 0 {
            notes.append("\(weight.isEmpty ? "自重" : weight + "kg") × \(reps)回" + (sets > 1 ? " × \(sets)セット" : ""))
        }
        let minutes = int(row["minutes"]) ?? 0
        return DailyEntry(
            id: id,
            day: day,
            time: String((string(row["happened_at"]) ?? "00:00").prefix(5)),
            kind: kind,
            title: title,
            groups: groups.filter(MealGroup.all.contains),
            note: notes.filter { !$0.isEmpty }.joined(separator: "\n"),
            amount: string(row["amount"]) ?? "",
            unit: string(row["unit"]) ?? "",
            minutes: minutes > 0 ? minutes : nil,
            isFavorite: bool(row["is_favorite"])
        )
    }

    // SQLite 由来の値は、数値が文字列だったり真偽値が 0/1 だったりするので緩く読む

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        double(value).map { Int($0.rounded()) }
    }

    private static func bool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.intValue != 0
        case let s as String: return s == "1" || s == "true"
        default: return false
        }
    }
}
