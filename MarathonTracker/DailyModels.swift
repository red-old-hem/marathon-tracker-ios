import Foundation

// 「日々をつくる」(Web版)から統合した、食事・習慣・体調・仕事メモ・週次レビュー。
// 日付はすべて TrackerStore.key(for:) の yyyy-MM-dd、週は月曜始まり(Web版と同じ)。
// 旧データとの互換性のため、各 struct に後から足すフィールドは RunLog と同じく Optional で末尾に置くこと。

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case meal
    case supplement
    /// Web版から取り込んだ過去の運動記録の表示用。新規の運動はラン・筋トレで記録する
    case exercise

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meal: return "食事"
        case .supplement: return "サプリ"
        case .exercise: return "運動"
        }
    }
}

enum MealGroup {
    static let all = ["主食", "肉・魚・卵・豆類", "野菜", "果物", "乳製品"]
}

struct DailyEntry: Codable, Identifiable, Equatable {
    var id: String
    var day: String
    /// HH:mm
    var time: String
    var kind: EntryKind
    var title: String
    var groups: [String] = []
    var note: String = ""
    var amount: String = ""
    var unit: String = ""
    var minutes: Int? = nil
    var isFavorite: Bool = false

    /// 「いつもの」で同じ記録とみなす中身。時刻・メモ・お気に入りは含めない
    var signature: String {
        [kind.rawValue, title, groups.joined(separator: ","), amount, unit, minutes.map(String.init) ?? ""]
            .joined(separator: "|")
    }

    var detail: String {
        var parts: [String] = []
        if !amount.isEmpty { parts.append(amount + unit) }
        if let minutes, minutes > 0 { parts.append("\(minutes)分") }
        if !groups.isEmpty { parts.append(groups.joined(separator: "・")) }
        return parts.joined(separator: " / ")
    }
}

enum HabitEnforcement: String, Codable, CaseIterable, Identifiable {
    case gentle
    case standard
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gentle: return "やさしい"
        case .standard: return "標準"
        case .strong: return "強い"
        }
    }
}

enum HabitStatus: String, Codable, CaseIterable, Identifiable {
    case done
    case small
    case partial
    case skip

    var id: String { rawValue }

    var label: String {
        switch self {
        case .done: return "できた"
        case .small: return "最小版"
        case .partial: return "一部"
        case .skip: return "見送り"
        }
    }

    /// 週次集計で「達成」に数えるか
    var counts: Bool { self == .done || self == .small }
}

struct Habit: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    /// いつやるか(きっかけ)
    var cue: String = ""
    /// できない日の最小版
    var minimum: String = ""
    var enforcement: HabitEnforcement = .gentle
    var archived: Bool = false
    var createdAt: String = ISO8601DateFormatter().string(from: Date())

    /// ひと言の入力が必要か。Web版と同じく、強いは常に、標準は一部・見送りのときだけ
    func requiresDetail(for status: HabitStatus) -> Bool {
        switch enforcement {
        case .gentle: return false
        case .standard: return status == .partial || status == .skip
        case .strong: return true
        }
    }
}

struct HabitCheck: Codable, Equatable {
    var habitId: String
    var day: String
    var status: HabitStatus
    var detail: String = ""

    static func storageKey(habitId: String, day: String) -> String { "\(day)|\(habitId)" }
    var storageKey: String { Self.storageKey(habitId: habitId, day: day) }
}

struct DailyMetric: Codable, Equatable {
    var day: String
    /// 手入力。ヘルスケア同期はこの3つを書き換えない
    var weightKg: Double? = nil
    var sleepHours: Double? = nil
    /// 1〜5(Web版と同じ。未入力は nil)
    var mood: Int? = nil
    /// ヘルスケア由来(RunLog の km / autoKm と同じく手入力と分けて持つ)
    var autoWeightKg: Double? = nil
    var autoSleepHours: Double? = nil
    var autoSteps: Int? = nil
    var autoRestingHR: Int? = nil

    /// 表示・集計用。手入力を優先する
    var weight: Double? { weightKg ?? autoWeightKg }
    var sleep: Double? { sleepHours ?? autoSleepHours }
    var steps: Int? { autoSteps }

    var isEmpty: Bool {
        weightKg == nil && sleepHours == nil && mood == nil &&
        autoWeightKg == nil && autoSleepHours == nil && autoSteps == nil && autoRestingHR == nil
    }
}

struct WorkNote: Codable, Equatable {
    var day: String
    /// 少し面白かった作業
    var fun: String
    /// 消耗した作業
    var drain: String
}

struct WeeklyReview: Codable, Equatable {
    var weekStart: String
    var wins: String = ""
    var lessons: String = ""
    var stopDoing: String = ""
    var nextPriority: String = ""

    var isEmpty: Bool {
        [wins, lessons, stopDoing, nextPriority].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// ヘルスケアの体調データの日次集計
struct HealthDaySummary: Equatable {
    var date: Date
    var weightKg: Double? = nil
    var sleepHours: Double? = nil
    var steps: Int? = nil
    var restingHR: Int? = nil
}

struct WeeklySummary: Equatable {
    var activeDays: Int
    var meals: Int
    var supplements: Int
    var habitDone: Int
    var habitTotal: Int
    var averageSleep: Double?
    var averageSteps: Int?
    var noteDays: Int
    var runKm: Double
    var runCount: Int
    var strengthCount: Int
}

enum DailyInputError: LocalizedError, Equatable {
    case emptyTitle
    case emptyNote
    case detailRequired
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "名前を入力してください"
        case .emptyNote: return "どちらか一つだけでも書いてください"
        case .detailRequired: return "この習慣は、ひと言の記録が必要です"
        case .invalidValue(let name): return "\(name)の値が正しくありません"
        }
    }
}

// MARK: - 操作

extension TrackerStore {
    static let noteMaxLength = 80

    static func newID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func timeString(_ date: Date) -> String {
        let comps = Plan.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    // MARK: 食事・サプリ

    func entries(on date: Date) -> [DailyEntry] {
        let day = key(for: date)
        return dailyEntries.values.filter { $0.day == day }.sorted { ($0.time, $0.id) < ($1.time, $1.id) }
    }

    func addEntry(_ entry: DailyEntry) throws {
        var entry = entry
        entry.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.title.isEmpty else { throw DailyInputError.emptyTitle }
        dailyEntries[entry.id] = entry
    }

    func removeEntry(id: String) {
        dailyEntries.removeValue(forKey: id)
    }

    func toggleFavorite(id: String) {
        guard var entry = dailyEntries[id] else { return }
        entry.isFavorite.toggle()
        dailyEntries[id] = entry
    }

    /// 「いつもの」。直近80件を中身ごとにまとめ、お気に入り→回数→新しさの順に上位を返す(Web版と同じ並び)
    func usualEntries(limit: Int = 6) -> [DailyEntry] {
        let recent = dailyEntries.values
            .filter { $0.kind != .exercise }
            .sorted { ($0.day, $0.time, $0.id) > ($1.day, $1.time, $1.id) }
            .prefix(80)
        var groups: [String: (latest: DailyEntry, count: Int, favorite: Bool, order: Int)] = [:]
        for (order, entry) in recent.enumerated() {
            if var group = groups[entry.signature] {
                group.count += 1
                group.favorite = group.favorite || entry.isFavorite
                groups[entry.signature] = group
            } else {
                groups[entry.signature] = (entry, 1, entry.isFavorite, order)
            }
        }
        return groups.values
            .sorted {
                if $0.favorite != $1.favorite { return $0.favorite }
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.order < $1.order
            }
            .prefix(limit)
            .map(\.latest)
    }

    /// 「いつもの」を今の時刻で記録し直す
    @discardableResult
    func repeatEntry(_ source: DailyEntry, at date: Date = Date()) -> DailyEntry {
        var copy = source
        copy.id = Self.newID()
        copy.day = key(for: date)
        copy.time = Self.timeString(date)
        copy.isFavorite = false
        dailyEntries[copy.id] = copy
        return copy
    }

    // MARK: 習慣

    var activeHabits: [Habit] {
        habits.values.filter { !$0.archived }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    var archivedHabits: [Habit] {
        habits.values.filter(\.archived).sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    func saveHabit(_ habit: Habit) throws {
        var habit = habit
        habit.title = habit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !habit.title.isEmpty else { throw DailyInputError.emptyTitle }
        habits[habit.id] = habit
    }

    func setHabitArchived(id: String, _ archived: Bool) {
        guard var habit = habits[id] else { return }
        habit.archived = archived
        habits[id] = habit
    }

    func deleteHabit(id: String) {
        habits.removeValue(forKey: id)
        habitChecks = habitChecks.filter { $0.value.habitId != id }
    }

    func habitCheck(habitId: String, on date: Date) -> HabitCheck? {
        habitChecks[HabitCheck.storageKey(habitId: habitId, day: key(for: date))]
    }

    func checkHabit(id: String, status: HabitStatus, detail: String = "", on date: Date) throws {
        guard let habit = habits[id] else { return }
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if habit.requiresDetail(for: status), detail.isEmpty { throw DailyInputError.detailRequired }
        let check = HabitCheck(habitId: id, day: key(for: date), status: status, detail: detail)
        habitChecks[check.storageKey] = check
    }

    func clearHabitCheck(id: String, on date: Date) {
        habitChecks.removeValue(forKey: HabitCheck.storageKey(habitId: id, day: key(for: date)))
    }

    // MARK: 体調

    func metric(on date: Date) -> DailyMetric? { metrics[key(for: date)] }

    /// 手入力の体調を保存する。ヘルスケア由来の値は残す
    func saveMetric(weightKg: Double?, sleepHours: Double?, mood: Int?, on date: Date) throws {
        if let weightKg, !(20...400).contains(weightKg) { throw DailyInputError.invalidValue("体重") }
        if let sleepHours, !(0...24).contains(sleepHours) { throw DailyInputError.invalidValue("睡眠") }
        if let mood, !(1...5).contains(mood) { throw DailyInputError.invalidValue("気分") }
        let day = key(for: date)
        var metric = metrics[day] ?? DailyMetric(day: day)
        metric.weightKg = weightKg
        metric.sleepHours = sleepHours
        metric.mood = mood
        metrics[day] = metric.isEmpty ? nil : metric
    }

    /// ヘルスケアの集計を auto* にだけ反映する。値の無い項目は既存値を残す(applyWorkouts と同じ方針)
    @discardableResult
    func applyHealthMetrics(_ summaries: [HealthDaySummary]) -> Int {
        var next = metrics
        var changed = 0
        for summary in summaries {
            let day = key(for: summary.date)
            var metric = next[day] ?? DailyMetric(day: day)
            let before = metric
            metric.autoWeightKg = summary.weightKg ?? metric.autoWeightKg
            metric.autoSleepHours = summary.sleepHours ?? metric.autoSleepHours
            metric.autoSteps = summary.steps ?? metric.autoSteps
            metric.autoRestingHR = summary.restingHR ?? metric.autoRestingHR
            guard metric != before, !metric.isEmpty else { continue }
            next[day] = metric
            changed += 1
        }
        if changed > 0 { metrics = next }
        return changed
    }

    // MARK: 30秒メモ

    func workNote(on date: Date) -> WorkNote? { workNotes[key(for: date)] }

    func saveWorkNote(fun: String, drain: String, on date: Date) throws {
        let fun = fun.trimmingCharacters(in: .whitespacesAndNewlines)
        let drain = drain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fun.isEmpty || !drain.isEmpty else { throw DailyInputError.emptyNote }
        guard fun.count <= Self.noteMaxLength, drain.count <= Self.noteMaxLength else {
            throw DailyInputError.invalidValue("メモ")
        }
        let day = key(for: date)
        workNotes[day] = WorkNote(day: day, fun: fun, drain: drain)
    }

    func removeWorkNote(on date: Date) {
        workNotes.removeValue(forKey: key(for: date))
    }

    /// 最近のメモ(新しい順)
    func recentWorkNotes(limit: Int = 7) -> [WorkNote] {
        workNotes.values.sorted { $0.day > $1.day }.prefix(limit).map { $0 }
    }

    // MARK: 週次レビュー

    func weeklyReview(weekOf date: Date) -> WeeklyReview? {
        weeklyReviews[key(for: Self.monday(of: date))]
    }

    func saveWeeklyReview(_ review: WeeklyReview) throws {
        guard !review.isEmpty else { throw DailyInputError.emptyNote }
        weeklyReviews[review.weekStart] = review
    }

    func weeklySummary(weekOf date: Date) -> WeeklySummary {
        let start = Self.monday(of: date)
        let days = (0..<7).compactMap { Plan.calendar.date(byAdding: .day, value: $0, to: start) }.map(key(for:))
        let daySet = Set(days)

        let entries = dailyEntries.values.filter { daySet.contains($0.day) }
        let checks = habitChecks.values.filter { daySet.contains($0.day) }
        let weekMetrics = days.compactMap { metrics[$0] }
        let weekLogs = days.compactMap { logs[$0] }

        var active = Set(entries.map(\.day))
        active.formUnion(checks.map(\.day))
        active.formUnion(weekMetrics.map(\.day))
        active.formUnion(days.filter { logs[$0] != nil })

        let sleeps = weekMetrics.compactMap(\.sleep).filter { $0 > 0 }
        let steps = weekMetrics.compactMap(\.steps).filter { $0 > 0 }
        let runs = weekLogs.filter { $0.type == .run || $0.type == .mini }
        let km = weekLogs.compactMap(\.distanceKm).reduce(0, +)

        return WeeklySummary(
            activeDays: active.count,
            meals: entries.filter { $0.kind == .meal }.count,
            supplements: entries.filter { $0.kind == .supplement }.count,
            habitDone: checks.filter(\.status.counts).count,
            habitTotal: checks.count,
            averageSleep: sleeps.isEmpty ? nil : (sleeps.reduce(0, +) / Double(sleeps.count) * 10).rounded() / 10,
            averageSteps: steps.isEmpty ? nil : steps.reduce(0, +) / steps.count,
            noteDays: days.filter { workNotes[$0] != nil }.count,
            runKm: (km * 10).rounded() / 10,
            runCount: runs.count,
            strengthCount: weekLogs.filter { $0.strength != nil }.count
        )
    }
}
