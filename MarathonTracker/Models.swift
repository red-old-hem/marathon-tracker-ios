import Foundation

struct WeekPlan {
    let phase: Int
    let km: Double
    let runs: [String]
    let tip: String
}

enum Plan {
    static let phases = ["基礎期", "走り込み期", "実戦期", "調整期"]

    /// 端末が和暦・仏暦設定でも計算が狂わないようグレゴリオ暦固定
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ja_JP")
        return cal
    }()

    static var start: Date { date(2026, 7, 6) }
    static var race: Date { date(2026, 11, 8) }

    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    static func weekIndex(of date: Date) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7.0))
    }

    static let weeks: [WeekPlan] = [
        WeekPlan(phase: 0, km: 16, runs: ["イージー40分", "イージー40分", "イージー50分"], tip: "ペースは気にしない。7:00〜7:30/kmで会話できる速さ。猛暑期なので早朝か夜に"),
        WeekPlan(phase: 0, km: 18, runs: ["イージー40分", "イージー40分", "イージー60分"], tip: "前夜にウェアと靴を玄関へ。朝の意思決定をゼロにする"),
        WeekPlan(phase: 0, km: 20, runs: ["イージー40分", "イージー50分", "イージー60分"], tip: "練習後30分以内に牛乳+おにぎり。回復が翌日のやる気になる"),
        WeekPlan(phase: 0, km: 15, runs: ["イージー40分", "イージー40分", "イージー40分"], tip: "回復週。少なく感じてOK、それが正解"),
        WeekPlan(phase: 0, km: 22, runs: ["イージー40分", "イージー50分", "イージー70分"], tip: "塩分補給も忘れずに。スポーツドリンクか塩タブレット"),
        WeekPlan(phase: 1, km: 25, runs: ["イージー40分", "イージー50分", "ロング走90分"], tip: "ロング走は距離でなく時間で管理。暑ければ途中歩いてOK"),
        WeekPlan(phase: 1, km: 27, runs: ["イージー40分", "イージー50分", "ロング走100分"], tip: "鉄分を意識。赤身肉・カツオ・小松菜"),
        WeekPlan(phase: 1, km: 20, runs: ["イージー40分", "イージー40分", "イージー60分"], tip: "回復週。疲労を抜くのも練習のうち"),
        WeekPlan(phase: 1, km: 30, runs: ["イージー40分", "ペース走20分 (5:45〜6:00/km)", "ロング走110分"], tip: "ペース走はアップ・ダウン各10分ジョグ込みで"),
        WeekPlan(phase: 1, km: 32, runs: ["イージー50分", "レースペース走8km (6:00〜6:20/km)", "ロング走120分"], tip: "ロング走でジェル補給の練習開始。本番と同じ銘柄で"),
        WeekPlan(phase: 1, km: 24, runs: ["イージー40分", "イージー50分", "イージー70分"], tip: "回復週。よく寝ること"),
        WeekPlan(phase: 2, km: 34, runs: ["イージー50分", "レースペース走10km", "ロング走120分"], tip: "ここから実戦期。涼しくなりペースが上がるのを実感できるはず"),
        WeekPlan(phase: 2, km: 36, runs: ["イージー50分", "ペース走20分", "30km走 (6:30〜7:00/km)"], tip: "30km走1回目。ジェル持参、抑えて入って後半崩れないこと優先"),
        WeekPlan(phase: 2, km: 28, runs: ["イージー40分", "レースペース走8km", "ロング走90分"], tip: "つなぎ週。疲労が残っていたら遠慮なく削る"),
        WeekPlan(phase: 2, km: 42, runs: ["イージー50分", "ペース走20分", "30km走 (6:20/kmで余裕を確認)"], tip: "30km走2回目。ここでサブ4か4.5かを最終判断する"),
        WeekPlan(phase: 2, km: 32, runs: ["イージー40分", "レースペース走10km", "ロング走90分"], tip: "ここから徐々に量を落とす。追い込みたくなるのを我慢"),
        WeekPlan(phase: 3, km: 22, runs: ["イージー40分", "レースペース走5km", "イージー60分"], tip: "物足りないくらいが正解。木曜からカーボローディング(主食1.5倍・脂質控えめ)"),
        WeekPlan(phase: 3, km: 12, runs: ["イージー30分", "2kmジョグ+流し3本", "本番 42.195km!"], tip: "前日は生もの禁止。当日はスタート3時間前に朝食、15分前にジェル、レース中は40分ごとに補給"),
    ]
}

/// その日の食事アドバイスを日付から自動判定する
enum Meals {
    static func tips(on date: Date) -> [String] {
        let cal = Plan.calendar
        let day = cal.startOfDay(for: date)
        let daysToRace = cal.dateComponents([.day], from: day, to: Plan.race).day ?? 999
        let weekday = cal.component(.weekday, from: day)
        let week = Plan.weekIndex(of: day)
        let phase = Plan.weeks[min(max(week, 0), Plan.weeks.count - 1)].phase

        if daysToRace < 0 {
            return ["完走おつかれさま。1〜2週間はしっかり食べてしっかり休む"]
        }
        if daysToRace == 0 {
            return ["スタート3時間前までに朝食(餅かおにぎり+バナナ)",
                    "スタート15分前にジェル1本",
                    "レース中は40〜45分ごとにジェル、給水は毎回取る"]
        }
        if daysToRace == 1 {
            return ["生もの・脂っこいもの・初めての店は避ける",
                    "消化の良い定番メニュー+主食多め",
                    "アルコールは我慢。水分をこまめに"]
        }
        if daysToRace <= 3 {
            return ["カーボローディング中: 主食を普段の1.5倍",
                    "脂質と食物繊維は控えめに",
                    "体重が1〜2kg増えるのは水分なので気にしない"]
        }

        var tips: [String] = []

        switch weekday {
        case 6 where phase >= 1: // 金: 翌日ロング走
            tips.append("明日のロング走に備えて夕食は主食多め")
        case 7: // 土: ロング走想定日
            if phase >= 1 {
                tips.append("ロング走2時間前におにぎり+バナナ")
                if week >= 9 {
                    tips.append("走行中は45分ごとにジェル(本番と同じ銘柄で練習)")
                }
            }
            tips.append("練習後30分以内に牛乳+おにぎり")
        case 3, 5: // 火・木: 練習日
            tips.append("練習後30分以内に牛乳+おにぎり or バナナ+ヨーグルト")
        default:
            break
        }

        switch phase {
        case 0:
            tips.append("3食とも主食+タンパク質20g以上。朝食を抜かない")
            tips.append("猛暑期: 練習前後は水分に加えて塩分も(スポドリか塩タブレット)")
        case 1:
            tips.append("鉄分を意識: 赤身肉・カツオ・レバー・小松菜")
            tips.append("3食とも主食+タンパク質20g以上")
        case 2:
            tips.append("走行量最大期。タンパク質と鉄分をしっかり、体重は落とそうとしない")
        default:
            tips.append("練習量が減る分、間食と脂質は控えめに。主食は減らさない")
        }

        return Array(tips.prefix(3))
    }
}

enum LogType: String, Codable {
    case run
    case mini
    /// 痛み警告中の休養。週の最低ラインにカウントする
    case rest
    /// ランをしなかった日の筋トレ記録。ランの集計には含めない
    case strength
}

enum BodyPart: String, Codable, CaseIterable, Identifiable {
    case knee, shin, sole, ankle, hip, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .knee: return "膝"
        case .shin: return "すね"
        case .sole: return "足裏"
        case .ankle: return "足首"
        case .hip: return "股関節"
        case .other: return "その他"
        }
    }
}

enum Feel: String, Codable, CaseIterable {
    case light, normal, heavy

    var label: String {
        switch self {
        case .light: return "軽い"
        case .normal: return "普通"
        case .heavy: return "重い"
        }
    }
}

enum StrengthCategory: String, Codable, CaseIterable, Identifiable {
    case upper, lower, core, full, mobility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upper: return "上半身"
        case .lower: return "下半身"
        case .core: return "体幹"
        case .full: return "全身"
        case .mobility: return "モビリティ"
        }
    }
}

enum SorenessArea: String, Codable, CaseIterable, Identifiable {
    case legs, glutes, back, chest, shoulders, arms, core

    var id: String { rawValue }

    var label: String {
        switch self {
        case .legs: return "脚"
        case .glutes: return "臀部"
        case .back: return "背中"
        case .chest: return "胸"
        case .shoulders: return "肩"
        case .arms: return "腕"
        case .core: return "体幹"
        }
    }
}

struct StrengthExercise: Codable, Equatable {
    var name: String
    /// 自重種目など重量を記録しない場合は nil
    var weightKg: Double? = nil
    var reps: Int
    var sets: Int
}

struct StrengthLog: Codable, Equatable {
    var category: StrengthCategory
    var templateName: String? = nil
    var exercises: [StrengthExercise]
    /// 主観的運動強度。1(とても楽)〜10(限界)
    var rpe: Int? = nil
    /// 当日の筋肉痛・張り
    var soreness: [SorenessArea]? = nil
}

struct StrengthTemplate: Identifiable {
    let name: String
    let category: StrengthCategory
    let exercises: [StrengthExercise]

    var id: String { name }

    /// エニタイムフィットネスで比較的導入例の多いマシン名を基準にする。
    /// 店舗によって機種・名称は異なるため、適用後に種目名は編集できる。
    static let presets: [StrengthTemplate] = [
        StrengthTemplate(name: "下半身マシン", category: .lower, exercises: [
            StrengthExercise(name: "レッグプレス", reps: 10, sets: 3),
            StrengthExercise(name: "シーテッド・レッグカール", reps: 10, sets: 3),
            StrengthExercise(name: "レッグエクステンション", reps: 10, sets: 2),
            StrengthExercise(name: "カーフレイズマシン", reps: 15, sets: 3),
        ]),
        StrengthTemplate(name: "上半身プッシュ", category: .upper, exercises: [
            StrengthExercise(name: "チェストプレス", reps: 10, sets: 3),
            StrengthExercise(name: "ショルダープレス", reps: 10, sets: 3),
            StrengthExercise(name: "ペックフライ", reps: 12, sets: 2),
        ]),
        StrengthTemplate(name: "上半身プル", category: .upper, exercises: [
            StrengthExercise(name: "ラットプルダウン", reps: 10, sets: 3),
            StrengthExercise(name: "シーテッドロー", reps: 10, sets: 3),
            StrengthExercise(name: "リアデルト／ペックフライ", reps: 12, sets: 2),
        ]),
        StrengthTemplate(name: "体幹・安定性マシン", category: .core, exercises: [
            StrengthExercise(name: "アブドミナルクランチ", reps: 12, sets: 3),
            StrengthExercise(name: "ロータリートルソー", reps: 12, sets: 2),
            StrengthExercise(name: "バックエクステンション", reps: 12, sets: 2),
        ]),
        StrengthTemplate(name: "全身マシン30分", category: .full, exercises: [
            StrengthExercise(name: "レッグプレス", reps: 10, sets: 2),
            StrengthExercise(name: "チェストプレス", reps: 10, sets: 2),
            StrengthExercise(name: "ラットプルダウン", reps: 10, sets: 2),
            StrengthExercise(name: "アブドミナルクランチ", reps: 12, sets: 2),
        ]),
    ]

    static func preset(named name: String) -> StrengthTemplate? {
        presets.first { $0.name == name }
    }
}

struct StrengthSuggestion {
    let template: StrengthTemplate?
    let title: String
    let reason: String
}

struct RunLog: Codable, Equatable {
    var type: LogType
    var menu: String? = nil
    /// 手入力の距離。ヘルスケア同期はこの値を書き換えない
    var km: Double? = nil
    /// ヘルスケアからの自動記録なら true(手動記録は nil)
    var auto: Bool? = nil
    var pains: [BodyPart]? = nil
    var feel: Feel? = nil

    // 以下は必ず Optional にし、必ず末尾に追加すること。
    // 合成 Codable は非Optional に decode を生成するためデフォルト値があっても
    // 旧JSONで throw し、TrackerStore.init の try? が全ログを nil にして保存データが消える。

    /// その日のヘルスケアのラン距離の合計 (km, 0.1刻み)
    var autoKm: Double? = nil
    /// 同・所要時間の合計(秒)。Double だと JSON に誤差が乗り Equatable 比較が不安定になる
    var autoSeconds: Int? = nil
    /// 取り込み済みワークアウトのUUID(昇順)。変更検知に使う
    var workoutIDs: [String]? = nil
    /// ランと同日に行った筋トレ。旧データとの互換性のため Optional のまま末尾に追加する
    var strength: StrengthLog? = nil
}

extension RunLog {
    /// 表示・集計に使う距離。ヘルスケア実測を優先し、無ければ手入力値
    var distanceKm: Double? { autoKm ?? km }

    var durationSeconds: Int? { autoSeconds }

    /// 秒/km。極端に短い記録はノイズなので弾く
    var paceSecPerKm: Double? {
        guard let km = distanceKm, km >= 0.5,
              let sec = autoSeconds, sec >= 60 else { return nil }
        return Double(sec) / km
    }

    var hasHealthDistance: Bool { autoKm != nil }
}

/// 表示書式。ビューからも通知からも使うのでドメイン側に置く
enum Format {
    /// 384.3 → "6:24/km"
    static func pace(_ secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }

    /// 3212 → "53分" / 4520 → "1時間15分"
    static func duration(seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }

    /// 6.0 → "6" / 6.5 → "6.5"
    static func km(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }
}

/// 参照用の目標ペース(秒/km)。42.195km 換算
enum PaceTarget {
    /// サブ4.5 = 4:30:00 → 6:24/km
    static let sub45: Double = 16200 / 42.195
    /// サブ4 = 4:00:00 → 5:41/km
    static let sub4: Double = 14400 / 42.195
}

/// ヘルスケアから取り込んだ1日分の集計(HealthKit非依存にして検証可能にする)
struct WorkoutDaySummary {
    let date: Date
    let km: Double?
    let seconds: Int?
    let workoutIDs: [String]
}

struct WorkoutApplyResult {
    let checkedDays: Int
    let changedDays: Int

    var changed: Bool { changedDays > 0 }
}

struct WeekStat: Identifiable {
    let week: Int
    let phase: Int
    /// プランの目標距離
    let targetKm: Double
    let actualKm: Double
    /// 距離と時間が両方揃ったログのみの合計(ペース算出用)
    let timedKm: Double
    let timedSeconds: Int

    var id: Int { week }
    var label: String { "W\(week + 1)" }

    /// 距離だけのログを混ぜると平均が壊れるので、揃っているログのみで算出
    var paceSecPerKm: Double? {
        guard timedKm >= 1, timedSeconds > 0 else { return nil }
        return Double(timedSeconds) / timedKm
    }
}

struct PainWarning: Equatable {
    let part: BodyPart
    let count: Int
    var severe: Bool { count >= 3 }
}

/// 完走済みのプランとは別に保持する次のレース目標。
struct NextGoal: Codable, Equatable {
    var name: String
    var date: Date
    var target: String? = nil
}

struct TrackerBackupEnvelope: Codable {
    var app: String
    var version: Int
    var exportedAt: String
    var data: TrackerBackupData
}

struct TrackerBackupData: Codable {
    var logs: [String: RunLog]
    var suppressedAutoDays: [String]?
    var nextGoal: NextGoal?
}

enum TrackerBackupError: LocalizedError {
    case invalidFormat
    case invalidDateKey(String)
    case invalidDistance(String)
    case invalidStrength(String)
    case invalidGoal
    case noImportableLogs

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "対応していないバックアップ形式です"
        case .invalidDateKey(let key):
            return "日付形式が不正です: \(key)"
        case .invalidDistance(let key):
            return "\(key) の距離が不正です"
        case .invalidStrength(let key):
            return "\(key) の筋トレ記録が不正です"
        case .invalidGoal:
            return "次の目標の内容が不正です"
        case .noImportableLogs:
            return "読み込める記録がありません"
        }
    }
}

@MainActor
final class TrackerStore: ObservableObject {
    @Published private(set) var logs: [String: RunLog] = [:] {
        didSet { persist() }
    }

    /// ユーザーが明示的に取り消したヘルスケア由来の日。同期で復活させない
    @Published private(set) var suppressedAutoDays: Set<String> = [] {
        didSet { userDefaults.set(Array(suppressedAutoDays), forKey: Self.suppressedKey) }
    }

    /// 岡山マラソン完走後に設定する、次のレースや挑戦の目標。
    @Published private(set) var nextGoal: NextGoal? {
        didSet { persistNextGoal() }
    }

    private static let storageKey = "mt-data"
    private static let suppressedKey = "mt-hk-suppressed"
    private static let nextGoalKey = "mt-next-goal"
    private let userDefaults: UserDefaults
    private let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Plan.calendar
        f.timeZone = Plan.calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        suppressedAutoDays = Set(userDefaults.stringArray(forKey: Self.suppressedKey) ?? [])
        if let data = userDefaults.data(forKey: Self.nextGoalKey) {
            nextGoal = try? JSONDecoder().decode(NextGoal.self, from: data)
        }
        if let data = userDefaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: RunLog].self, from: data) {
            let migrated = Self.migrateLegacyAutoLogs(decoded)
            logs = migrated
            // init 内の代入では didSet が呼ばれないので明示的に保存する
            if migrated != decoded { persist() }
        }
    }

    /// 旧sync が km に入れていたヘルスケア由来の距離を autoKm へ移す。
    /// 条件自体が冪等なのでバージョンフラグは不要
    private static func migrateLegacyAutoLogs(_ raw: [String: RunLog]) -> [String: RunLog] {
        var out = raw
        for (k, var log) in raw where log.auto == true && log.autoKm == nil && log.km != nil {
            log.autoKm = log.km
            log.km = nil
            out[k] = log
        }
        return out
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(logs) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    private func persistNextGoal() {
        guard let nextGoal else {
            userDefaults.removeObject(forKey: Self.nextGoalKey)
            return
        }
        if let data = try? JSONEncoder().encode(nextGoal) {
            userDefaults.set(data, forKey: Self.nextGoalKey)
        }
    }

    func setNextGoal(_ goal: NextGoal) {
        nextGoal = goal
    }

    func clearNextGoal() {
        nextGoal = nil
    }

    func key(for date: Date) -> String { keyFormatter.string(from: date) }

    func log(on date: Date) -> RunLog? { logs[key(for: date)] }

    func record(_ log: RunLog, on date: Date) {
        suppressedAutoDays.remove(key(for: date))
        logs[key(for: date)] = log
    }

    func remove(on date: Date) {
        let k = key(for: date)
        if let log = logs[k], log.auto == true || log.autoKm != nil {
            suppressedAutoDays.insert(k)
        }
        logs.removeValue(forKey: k)
    }

    /// ラン記録を削除する。筋トレが同日にあれば筋トレだけを残す。
    func removeRunRecord(on date: Date) {
        let k = key(for: date)
        guard let log = logs[k], log.type != .strength else { return }
        if log.auto == true || log.autoKm != nil {
            suppressedAutoDays.insert(k)
        }
        if let strength = log.strength {
            logs[k] = RunLog(type: .strength, strength: strength)
        } else {
            logs.removeValue(forKey: k)
        }
    }

    func recordStrength(_ strength: StrengthLog, on date: Date) {
        let k = key(for: date)
        if var log = logs[k] {
            log.strength = strength
            logs[k] = log
        } else {
            logs[k] = RunLog(type: .strength, strength: strength)
        }
    }

    /// 筋トレだけの日を削除する場合は、その日のログ自体を取り除く。
    func removeStrength(on date: Date) {
        let k = key(for: date)
        guard var log = logs[k] else { return }
        log.strength = nil
        if log.type == .strength {
            if log.auto == true || log.autoKm != nil {
                log.type = .run
                log.menu = nextMenu(on: date)
                logs[k] = log
            } else {
                logs.removeValue(forKey: k)
            }
        } else {
            logs[k] = log
        }
    }

    /// ヘルスケアの日次集計を取り込む。手動入力(type / menu / km / pains / feel)は変更しない。
    /// 毎回ソースから日単位で再計算するので冪等。workoutIDs は無駄な書き込みを避ける変更検知に使う。
    /// ワークアウトが存在する日しか走査しないため、権限剥奪や削除で既存の autoKm が消えることはない。
    @discardableResult
    func applyWorkouts(_ summaries: [WorkoutDaySummary]) -> WorkoutApplyResult {
        var next = logs
        var checkedDays = 0
        var changedDays = 0

        for summary in summaries.sorted(by: { $0.date < $1.date }) {
            let k = key(for: summary.date)
            if suppressedAutoDays.contains(k) { continue }
            checkedDays += 1
            let ids = summary.workoutIDs.sorted()

            if var existing = next[k] {
                if (existing.workoutIDs ?? []) == ids,
                   existing.autoKm == summary.km,
                   existing.autoSeconds == summary.seconds {
                    continue
                }
                // type / menu / km / pains / feel は触らない。.mini も .rest も
                // ユーザーの申告のまま残し、距離と時間だけが正しくなる。
                // nil への降格もしない(距離なしワークアウトで既存値を失わないため)
                // ただし筋トレだけの日はランの実績が確定したので .run に昇格する。
                if existing.type == .strength {
                    existing.type = .run
                    existing.menu = nextMenu(on: summary.date, in: next)
                }
                existing.autoKm = summary.km ?? existing.autoKm
                existing.autoSeconds = summary.seconds ?? existing.autoSeconds
                existing.workoutIDs = ids
                next[k] = existing
            } else {
                next[k] = RunLog(
                    type: .run,
                    menu: nextMenu(on: summary.date, in: next),
                    auto: true,
                    autoKm: summary.km,
                    autoSeconds: summary.seconds,
                    workoutIDs: ids
                )
            }
            changedDays += 1
        }

        // 代入は1回だけ = 永続化も1回
        if changedDays > 0 { logs = next }
        return WorkoutApplyResult(checkedDays: checkedDays, changedDays: changedDays)
    }

    // MARK: - 週の計算

    func weekIndex(of date: Date) -> Int {
        Plan.weekIndex(of: date)
    }

    func weekDates(_ week: Int) -> [Date] {
        let cal = Plan.calendar
        let monday = cal.date(byAdding: .day, value: week * 7, to: Plan.start)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }

    // 以下3組は applyWorkouts が作業中の辞書を渡せるようスナップショット版を持つ。
    // 同一バッチで複数日を新規作成するとき、logs はまだ更新されていないため
    // 作業中の辞書を見ないと全日に同じメニューが割り当たってしまう。
    private func weekLogs(_ week: Int, in source: [String: RunLog]) -> [RunLog] {
        weekDates(week).compactMap { source[key(for: $0)] }
            .filter { $0.type != .strength }
    }

    func weekLogs(_ week: Int) -> [RunLog] { weekLogs(week, in: logs) }

    func weekAchieved(_ week: Int) -> Bool { weekLogs(week).count >= 2 }

    func weekKm(_ week: Int) -> Double {
        weekLogs(week).compactMap(\.distanceKm).reduce(0, +)
    }

    /// 同名メニューが週に複数ある場合に対応した消化数
    private func menuDoneCounts(week: Int, in source: [String: RunLog]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for log in weekLogs(week, in: source) where log.type == .run {
            if let menu = log.menu { counts[menu, default: 0] += 1 }
        }
        return counts
    }

    func menuDoneCounts(week: Int) -> [String: Int] { menuDoneCounts(week: week, in: logs) }

    /// 直近のラン記録から連続する痛みを検出(休養記録は数えず、途切れさせもしない)。
    /// 最新のランが痛みなしなら警告なし。
    func painWarning() -> PainWarning? {
        let recentRuns = logs.sorted { $0.key > $1.key }
            .map(\.value)
            .filter { $0.type == .run || $0.type == .mini }
        guard let latest = recentRuns.first,
              let latestPains = latest.pains, !latestPains.isEmpty else { return nil }

        var worst: PainWarning?
        for part in latestPains {
            var count = 0
            for log in recentRuns {
                if (log.pains ?? []).contains(part) { count += 1 } else { break }
            }
            if count >= 2 && count > (worst?.count ?? 0) {
                worst = PainWarning(part: part, count: count)
            }
        }
        return worst
    }

    /// 既存の記録に痛み情報を後から追記・編集する
    func updatePains(_ pains: [BodyPart], on date: Date) {
        guard var log = logs[key(for: date)] else { return }
        log.pains = pains.isEmpty ? nil : pains
        logs[key(for: date)] = log
    }

    /// その日が属する週の未消化メニューのうち先頭のもの
    private func nextMenu(on date: Date, in source: [String: RunLog]) -> String? {
        let week = min(max(weekIndex(of: date), 0), Plan.weeks.count - 1)
        let counts = menuDoneCounts(week: week, in: source)
        var seen: [String: Int] = [:]
        for run in Plan.weeks[week].runs {
            seen[run, default: 0] += 1
            if counts[run, default: 0] < seen[run]! { return run }
        }
        return nil
    }

    func nextMenu(on date: Date) -> String? { nextMenu(on: date, in: logs) }

    func streak(today: Date) -> Int {
        let cur = weekIndex(of: today)
        guard cur >= 0 else { return 0 }
        var count = 0
        var w = min(cur, Plan.weeks.count - 1)
        while w >= 0 {
            if weekAchieved(w) {
                count += 1
            } else if w != cur {
                break
            }
            w -= 1
        }
        return count
    }

    var totalRuns: Int { logs.values.filter { $0.type == .run || $0.type == .mini }.count }
    var totalStrengthSessions: Int { logs.values.filter { $0.strength != nil }.count }

    /// ランの予定、故障兆候、直近の筋トレ負荷から当日に合うマシンメニューを選ぶ。
    func strengthSuggestion(on date: Date) -> StrengthSuggestion {
        if let warning = painWarning() {
            return StrengthSuggestion(
                template: nil,
                title: "今日は筋トレも休養",
                reason: "\(warning.part.label)の痛みが続いています。回復を優先しましょう"
            )
        }

        let todayLog = log(on: date)
        let lowerBodyPain: Set<BodyPart> = [.knee, .shin, .sole, .ankle, .hip]
        if !(Set(todayLog?.pains ?? []).intersection(lowerBodyPain)).isEmpty {
            return upperBodySuggestion(reason: "ランで下半身の痛みを記録しています。脚に負荷をかけない内容です")
        }

        let recentStrength = (1...2).compactMap { offset -> StrengthLog? in
            guard let day = Plan.calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return log(on: day)?.strength
        }
        let lowerBodySoreness: Set<SorenessArea> = [.legs, .glutes]
        let needsLowerBodyRecovery = recentStrength.contains {
            ($0.category == .lower || $0.category == .full) &&
            (($0.rpe ?? 0) >= 7 || !(Set($0.soreness ?? []).intersection(lowerBodySoreness)).isEmpty)
        }
        if needsLowerBodyRecovery {
            return upperBodySuggestion(reason: "直近2日間に下半身の高負荷または筋肉痛があります")
        }

        let menu = todayLog?.menu ?? ""
        let demandingRun = ["ロング", "30km", "ペース走", "レースペース", "本番"].contains { menu.contains($0) }
        if demandingRun {
            return upperBodySuggestion(reason: "今日は\(menu)のため、脚を使わないマシンメニューです")
        }

        let weekday = Plan.calendar.component(.weekday, from: date)
        if weekday == 7 {
            return upperBodySuggestion(reason: "ロング走想定日なので、脚への追加負荷を避けます")
        }
        if weekday == 3 || weekday == 5 {
            return suggestion(named: "体幹・安定性マシン", title: "今日の提案", reason: "ラン想定日はフォームを支える体幹を短時間で")
        }

        guard let lastStrength = logs.sorted(by: { $0.key > $1.key })
            .first(where: { $0.key < key(for: date) })?.value.strength else {
            return suggestion(named: "全身マシン30分", title: "今日の提案", reason: "最初の1回は全身を軽めに動かすメニューです")
        }

        switch lastStrength.category {
        case .lower, .full:
            return upperBodySuggestion(reason: "前回は\(lastStrength.category.label)でした。部位を分けて回復時間を確保します")
        case .upper:
            return suggestion(named: "下半身マシン", title: "今日の提案", reason: "前回は上半身でした。ランに必要な脚をマシンで補強します")
        case .core, .mobility:
            return suggestion(named: "下半身マシン", title: "今日の提案", reason: "直近は体幹中心でした。下半身を補強する日にします")
        }
    }

    private func upperBodySuggestion(reason: String) -> StrengthSuggestion {
        let lastName = logs.sorted(by: { $0.key > $1.key })
            .compactMap(\.value.strength?.templateName)
            .first
        let name = lastName == "上半身プッシュ" ? "上半身プル" : "上半身プッシュ"
        return suggestion(named: name, title: "今日の提案", reason: reason)
    }

    private func suggestion(named name: String, title: String, reason: String) -> StrengthSuggestion {
        StrengthSuggestion(template: StrengthTemplate.preset(named: name), title: title, reason: reason)
    }
}

// MARK: - バックアップ

extension TrackerStore {
    func exportBackupData() throws -> Data {
        let payload = TrackerBackupEnvelope(
            app: "okayama-marathon-18-week-trainer-ios",
            version: 3,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            data: TrackerBackupData(
                logs: logs,
                suppressedAutoDays: Array(suppressedAutoDays).sorted(),
                nextGoal: nextGoal
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    func importPreviewCount(from data: Data) throws -> Int {
        let backup = try Self.decodeBackupData(from: data)
        try Self.validateBackup(backup)
        return backup.logs.count
    }

    @discardableResult
    func importBackupData(_ data: Data) throws -> Int {
        let backup = try Self.decodeBackupData(from: data)
        try Self.validateBackup(backup)

        suppressedAutoDays = Set((backup.suppressedAutoDays ?? []).filter(Self.isValidDateKey))
        nextGoal = backup.nextGoal
        logs = backup.logs
        return backup.logs.count
    }

    private static func decodeBackupData(from data: Data) throws -> TrackerBackupData {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(TrackerBackupEnvelope.self, from: data) {
            return envelope.data
        }
        if let backupData = try? decoder.decode(TrackerBackupData.self, from: data) {
            return backupData
        }
        if let logs = try? decoder.decode([String: RunLog].self, from: data) {
            return TrackerBackupData(logs: logs, suppressedAutoDays: nil, nextGoal: nil)
        }
        throw TrackerBackupError.invalidFormat
    }

    private static func validateBackup(_ backup: TrackerBackupData) throws {
        guard !backup.logs.isEmpty else { throw TrackerBackupError.noImportableLogs }
        for (key, log) in backup.logs {
            guard isValidDateKey(key) else { throw TrackerBackupError.invalidDateKey(key) }
            if let km = log.km, !isValidDistance(km) { throw TrackerBackupError.invalidDistance(key) }
            if let autoKm = log.autoKm, !isValidDistance(autoKm) { throw TrackerBackupError.invalidDistance(key) }
            if let strength = log.strength, !isValidStrength(strength) {
                throw TrackerBackupError.invalidStrength(key)
            }
        }
        if let goal = backup.nextGoal, !isValidGoal(goal) {
            throw TrackerBackupError.invalidGoal
        }
    }

    private static func isValidDistance(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    private static func isValidStrength(_ value: StrengthLog) -> Bool {
        guard value.rpe == nil || (1...10).contains(value.rpe!), !value.exercises.isEmpty else { return false }
        return value.exercises.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.reps > 0 && $0.sets > 0 &&
            ($0.weightKg == nil || ($0.weightKg!.isFinite && $0.weightKg! >= 0))
        }
    }

    private static func isValidGoal(_ value: NextGoal) -> Bool {
        !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        value.target?.count ?? 0 <= 80
    }

    private static func isValidDateKey(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Plan.calendar
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

// MARK: - 距離の集計

extension TrackerStore {
    func stat(week: Int) -> WeekStat {
        let plan = Plan.weeks[min(max(week, 0), Plan.weeks.count - 1)]
        var actual = 0.0
        var timedKm = 0.0
        var timedSeconds = 0
        for log in weekLogs(week) {
            if let km = log.distanceKm { actual += km }
            // 時間の無いログを混ぜるとペースが壊れるので、揃っているものだけ足す
            if log.paceSecPerKm != nil, let km = log.distanceKm, let sec = log.durationSeconds {
                timedKm += km
                timedSeconds += sec
            }
        }
        return WeekStat(week: week, phase: plan.phase, targetKm: plan.km,
                        actualKm: (actual * 10).rounded() / 10,
                        timedKm: timedKm, timedSeconds: timedSeconds)
    }

    var weekStats: [WeekStat] { (0..<Plan.weeks.count).map { stat(week: $0) } }

    var totalKm: Double {
        (logs.values.compactMap(\.distanceKm).reduce(0, +) * 10).rounded() / 10
    }

    /// 全期間の平均ペース。距離と時間が揃ったログのみ
    var averagePaceSecPerKm: Double? {
        let timed = logs.values.compactMap { log -> (Double, Int)? in
            guard log.paceSecPerKm != nil,
                  let km = log.distanceKm, let sec = log.durationSeconds else { return nil }
            return (km, sec)
        }
        let km = timed.reduce(0.0) { $0 + $1.0 }
        let sec = timed.reduce(0) { $0 + $1.1 }
        guard km >= 1 else { return nil }
        return Double(sec) / km
    }
}
