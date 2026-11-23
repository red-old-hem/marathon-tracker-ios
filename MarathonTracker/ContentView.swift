import SwiftUI
import UniformTypeIdentifiers

struct DataBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: TrackerStore

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }
    private var currentWeek: Int { store.weekIndex(of: today) }
    private var menuWeek: Int { min(max(currentWeek, 0), Plan.weeks.count - 1) }
    private var inPlan: Bool { currentWeek >= 0 && currentWeek < Plan.weeks.count }
    private var isPostRace: Bool { today > Plan.race }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HeaderView(currentWeek: currentWeek, inPlan: inPlan)
                if isPostRace {
                    // レース後は新しいトレーニングの記録。岡山の18週は記録シートで見返す
                    NextGoalCard()
                    PainBanner()
                    TodayCard()
                    GaugeCard(currentWeek: currentWeek, menuWeek: menuWeek, inPlan: inPlan)
                    HealthCard()
                    StatsCard()
                    if !postRaceChartWeeks.isEmpty {
                        DistanceChartCard(weeks: postRaceChartWeeks)
                    }
                    CalendarCard(title: postRaceCalendarTitle, weeks: postRaceWeeks)
                    OkayamaArchiveCard()
                    DataBackupCard()
                        .padding(.bottom, 8)
                } else {
                    PainBanner()
                    TodayCard()
                    GaugeCard(currentWeek: currentWeek, menuWeek: menuWeek, inPlan: inPlan)
                    MenuCard(menuWeek: menuWeek)
                    MealCard()
                    HealthCard()
                    StatsCard()
                    DistanceChartCard()
                    CalendarCard(title: "18週間カレンダー", weeks: Array(0..<Plan.weeks.count))
                    DataBackupCard()
                    Text("目標: サブ4.5を確実に、10月の30km走の結果でサブ4を判断")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var postRaceCalendarTitle: String {
        guard let goal = store.nextGoal else { return "レース後のトレーニング" }
        return "\(goal.name) に向けて"
    }

    /// 週別距離グラフはレース翌週〜今週(古い順、直近26週まで)。目標日を過ぎても今週まで出す
    private var postRaceChartWeeks: [Int] {
        let first = Plan.weeks.count
        guard currentWeek >= first else { return [] }
        return Array(max(first, currentWeek - 25)...currentWeek)
    }

    /// 次の目標があれば目標日の週まで先に並べる(18週カレンダーと同じく古い週が上)。
    /// 目標がなければレース翌週から直近12週(新しい週が上)
    private var postRaceWeeks: [Int] {
        if let training = store.nextGoalTraining(today: today) { return training.plannedWeeks }
        let first = Plan.weeks.count
        guard currentWeek >= first else { return [] }
        return Array((max(first, currentWeek - 11)...currentWeek).reversed())
    }
}

// MARK: - ヘッダー

struct HeaderView: View {
    @EnvironmentObject private var store: TrackerStore
    let currentWeek: Int
    let inPlan: Bool

    private var daysToRace: Int {
        Plan.calendar.dateComponents([.day], from: today, to: displayDate).day ?? 0
    }

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }
    private var isPostRace: Bool { today > Plan.race }
    private var nextGoal: NextGoal? { isPostRace ? store.nextGoal : nil }
    private var displayDate: Date { nextGoal?.date ?? Plan.race }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(nextGoal?.name ?? "おかやまマラソン 2026")
                    .font(.headline)
                Spacer()
                Text(nextGoal != nil ? "次の目標"
                     : isPostRace ? "レース後"
                     : Plan.phases[Plan.weeks[min(max(currentWeek, 0), Plan.weeks.count - 1)].phase])
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }
            HStack(alignment: .firstTextBaseline) {
                if daysToRace > 0 {
                    Text("\(daysToRace)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("日後が本番")
                        .foregroundStyle(.secondary)
                } else if daysToRace == 0 {
                    Text(nextGoal == nil ? "本番当日!" : "目標当日!")
                        .font(.system(size: 34, weight: .bold))
                } else {
                    Text(nextGoal == nil ? "完走おめでとう 🎉" : "目標日を過ぎました")
                        .font(.system(size: 28, weight: .bold))
                }
                Spacer()
                Text(headerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !isPostRace {
                HStack(spacing: 3) {
                    ForEach(Array(Plan.weeks.enumerated()), id: \.offset) { i, week in
                        Capsule()
                            .fill(phaseColor(week.phase))
                            .opacity(i <= currentWeek ? 1 : 0.25)
                            .frame(height: 6)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var headerDetail: String {
        if let goal = nextGoal { return goal.target ?? "開催日まで" }
        return inPlan ? "第\(currentWeek + 1)週 / \(Plan.weeks.count)週" : (currentWeek < 0 ? "7/6(月)プラン開始" : "プラン終了")
    }
}

// MARK: - 次の目標

struct NextGoalCard: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingEditor = false

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("次の目標", systemImage: "flag.checkered")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
                Spacer()
                if store.nextGoal != nil {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline.bold())
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .accessibilityLabel("次の目標を編集")
                }
            }

            if let goal = store.nextGoal {
                Text(goal.name)
                    .font(.title3.bold())
                HStack(spacing: 8) {
                    Label(dateText(goal.date), systemImage: "calendar")
                    Label(daysText(until: goal.date), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let target = goal.target, !target.isEmpty {
                    Text(target)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                if let training = store.nextGoalTraining(today: today) {
                    trainingSummary(training)
                }
            } else {
                Text("次のレースや挑戦を設定すると、レース後のランがその目標に向けたトレーニング記録になります")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("次の目標を設定") {
                    showingEditor = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showingEditor) {
            NextGoalEditor()
                .environmentObject(store)
        }
    }

    /// 目標に向けたトレーニングの積み上げ
    private func trainingSummary(_ training: GoalTraining) -> some View {
        HStack(spacing: 8) {
            summaryItem("\(training.weeks.count)週目", "トレーニング")
            summaryItem("\(training.runs)回", "ラン")
            summaryItem("\(Format.km(training.km))km", "距離")
            summaryItem("\(training.achievedWeeks)週", "週2回達成")
        }
    }

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Plan.calendar
        f.dateFormat = "yyyy年M月d日 (E)"
        return f.string(from: date)
    }

    private func daysText(until date: Date) -> String {
        let days = Plan.calendar.dateComponents([.day], from: today, to: date).day ?? 0
        if days > 0 { return "あと\(days)日" }
        if days == 0 { return "今日" }
        return "\(-days)日前"
    }
}

struct NextGoalEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Plan.calendar.date(byAdding: .month, value: 6, to: Date())!
    @State private var target = ""
    @State private var errorMessage: String?
    @State private var loaded = false

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            Form {
                Section("レース・挑戦") {
                    TextField("例: 神戸マラソン 2027", text: $name)
                    DatePicker("開催日", selection: $date, in: today..., displayedComponents: .date)
                    TextField("目標（任意・例: 4時間30分）", text: $target)
                }

                if store.nextGoal != nil {
                    Section {
                        Button("次の目標を削除", role: .destructive) {
                            store.clearNextGoal()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(store.nextGoal == nil ? "次の目標を設定" : "次の目標を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("入力エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: loadOnce)
        }
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let goal = store.nextGoal else { return }
        name = goal.name
        date = goal.date
        target = goal.target ?? ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "レース名または目標名を入力してください"
            return
        }
        guard date >= today else {
            errorMessage = "開催日は今日以降を選択してください"
            return
        }
        guard trimmedTarget.count <= 80 else {
            errorMessage = "目標は80文字以内で入力してください"
            return
        }
        store.setNextGoal(NextGoal(name: trimmedName, date: date,
                                   target: trimmedTarget.isEmpty ? nil : trimmedTarget))
        dismiss()
    }
}

func phaseColor(_ phase: Int) -> Color {
    switch phase {
    case 0: return Color(red: 0.36, green: 0.79, blue: 0.65)
    case 1: return Color(red: 0.11, green: 0.62, blue: 0.46)
    case 2: return Color(red: 0.22, green: 0.54, blue: 0.87)
    default: return Color(red: 0.94, green: 0.62, blue: 0.15)
    }
}

// MARK: - 痛み警告バナー

struct PainBanner: View {
    @EnvironmentObject private var store: TrackerStore

    var body: some View {
        if let warning = store.painWarning() {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(warning.severe
                         ? "\(warning.part.label)の痛みが\(warning.count)回連続"
                         : "\(warning.part.label)の痛みが2回続いています")
                        .font(.subheadline.bold())
                    Text(warning.severe
                         ? "2〜3日完全休養を。痛みが引かないまま走り込むのが一番危険。長引くなら整形外科へ"
                         : "次のポイント練習はやめて、短いジョグか休養に切り替えを")
                        .font(.caption)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((warning.severe ? Color.red : Color.orange).opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(warning.severe ? .red : .orange)
        }
    }
}

// MARK: - 痛みチップ

struct PainChips: View {
    @Binding var selection: Set<BodyPart>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(BodyPart.allCases) { part in
                let selected = selection.contains(part)
                Button {
                    if selected { selection.remove(part) } else { selection.insert(part) }
                } label: {
                    Text(part.label)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Color.red.opacity(0.15) : Color(.systemGroupedBackground),
                                    in: Capsule())
                        .foregroundStyle(selected ? .red : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 今日のチェックイン

struct TodayCard: View {
    @EnvironmentObject private var store: TrackerStore

    @State private var showingForm = false
    @State private var selectedMenu = ""
    @State private var kmText = ""
    @State private var selectedPains: Set<BodyPart> = []
    @State private var feel: Feel?
    @State private var showingPainEditor = false

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }
    /// 筋トレは筋トレタブで扱う。筋トレだけの日はランの記録なしとして表示する
    private var todayLog: RunLog? { store.runLog(on: today) }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Plan.calendar
        f.dateFormat = "M/d (E)"
        return f.string(from: today)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(dateLabel).font(.headline)
                Spacer()
                Text("今日").font(.caption).foregroundStyle(.secondary)
            }

            if let log = todayLog, !showingForm {
                Label(statusText(log), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.green)
                if let pains = log.pains, !pains.isEmpty {
                    Text("痛み: \(pains.map(\.label).joined(separator: "・"))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if log.type != .rest {
                    if showingPainEditor {
                        PainChips(selection: $selectedPains)
                        Button {
                            store.updatePains(Array(selectedPains), on: today)
                            NotificationManager.reschedule(store: store)
                            showingPainEditor = false
                        } label: {
                            Text("痛みを保存").bold().frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        Button("痛みを追記・編集") {
                            selectedPains = Set(log.pains ?? [])
                            showingPainEditor = true
                        }
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(minHeight: 40)
                    }
                }
                Button("今日のラン記録を取り消す") {
                    store.removeRunRecord(on: today)
                    NotificationManager.reschedule(store: store)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            } else if showingForm {
                VStack(alignment: .leading, spacing: 8) {
                    Text("どのメニュー?").font(.caption).foregroundStyle(.secondary)
                    Picker("メニュー", selection: $selectedMenu) {
                        ForEach(Array(menuOptions.enumerated()), id: \.offset) { _, option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("距離 (km・わかれば)").font(.caption).foregroundStyle(.secondary)
                    TextField("例: 6.5", text: $kmText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("どこか痛む?(任意)").font(.caption).foregroundStyle(.secondary)
                    PainChips(selection: $selectedPains)
                    Text("調子(任意)").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(Feel.allCases, id: \.self) { f in
                            let selected = feel == f
                            Button {
                                feel = selected ? nil : f
                            } label: {
                                Text(f.label)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selected ? Color.green.opacity(0.2) : Color(.systemGroupedBackground),
                                                in: Capsule())
                                    .foregroundStyle(selected ? .green : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Button {
                            save()
                        } label: {
                            Text("記録する")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        Button("やめる") { showingForm = false }
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        prepareForm()
                    } label: {
                        Text("走った")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        store.record(preservingAttachedFields(RunLog(type: .mini, menu: nil, km: nil)), on: today)
                        NotificationManager.reschedule(store: store)
                    } label: {
                        Text("5分だけ走った")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
                if store.painWarning() != nil {
                    Button {
                        store.record(preservingAttachedFields(RunLog(type: .rest)), on: today)
                        NotificationManager.reschedule(store: store)
                    } label: {
                        Text("痛みで休んだ(達成扱い)")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                Text("迷ったら「5分だけ」でOK。ゼロの日を作らないのが勝ち")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var menuOptions: [String] { store.menuOptions(on: today) }

    private func prepareForm() {
        selectedMenu = store.defaultMenu(on: today)
        kmText = ""
        selectedPains = []
        feel = nil
        showingForm = true
    }

    private func save() {
        let km = Double(kmText.replacingOccurrences(of: ",", with: "."))
        store.record(
            preservingAttachedFields(RunLog(type: .run, menu: selectedMenu, km: km,
                                             pains: selectedPains.isEmpty ? nil : Array(selectedPains), feel: feel)),
            on: today
        )
        NotificationManager.reschedule(store: store)
        showingForm = false
    }

    private func statusText(_ log: RunLog) -> String {
        if log.type == .rest {
            return "痛みで休んだ。正しい判断、今日も達成"
        }
        if log.type == .mini {
            return "5分だけでも走った。今日も勝ち"
        }
        var text = "走った"
        if let menu = log.menu { text += " \(menu)" }
        if let km = log.distanceKm { text += " / \(Format.km(km))km" }
        if let sec = log.durationSeconds { text += " \(Format.duration(seconds: sec))" }
        if let pace = log.paceSecPerKm {
            text += " \(Format.pace(pace))"
            // 目標比較はペース練習のときだけ。イージーランで出すと
            // 設計通り遅く走っている日に毎回ダメ出しすることになる
            if let menu = log.menu, menu.contains("ペース走") || menu.contains("レースペース") {
                if pace <= PaceTarget.sub4 { text += "(サブ4圏内)" }
                else if pace <= PaceTarget.sub45 { text += "(サブ4.5圏内)" }
            }
        }
        if log.hasHealthDistance { text += "(ヘルスケア)" }
        return text
    }

    private func preservingAttachedFields(_ log: RunLog) -> RunLog {
        guard let existing = store.log(on: today) else { return log }
        var next = log
        next.auto = existing.auto
        next.autoKm = existing.autoKm
        next.autoSeconds = existing.autoSeconds
        next.workoutIDs = existing.workoutIDs
        next.strength = existing.strength
        return next
    }
}

// MARK: - ゲージ

struct GaugeCard: View {
    @EnvironmentObject private var store: TrackerStore
    let currentWeek: Int
    let menuWeek: Int
    let inPlan: Bool

    var body: some View {
        // レース後の週も月曜始まりで数える(目標距離はなし)
        let counted = inPlan || currentWeek >= Plan.weeks.count
        let runCount = counted ? store.weekLogs(currentWeek).count : 0
        let km = counted ? store.weekKm(currentWeek) : 0
        let target: Double? = inPlan || currentWeek < 0 ? Plan.weeks[menuWeek].km : nil

        VStack(spacing: 14) {
            VStack(spacing: 6) {
                HStack {
                    Text("今週の最低ライン").font(.subheadline.bold())
                    Spacer()
                    Text("\(runCount) / 2回\(runCount >= 2 ? " 達成!" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(Double(runCount) / 2, 1))
                    .tint(.green)
            }
            VStack(spacing: 6) {
                HStack {
                    Text("今週の距離").font(.subheadline.bold())
                    Spacer()
                    if let target {
                        Text("\((km * 10).rounded() / 10, format: .number) / \(target, format: .number)km 目安")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Format.km(km))km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let target {
                    ProgressView(value: min(km / target, 1))
                        .tint(.blue)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 今週のメニュー

struct MenuCard: View {
    @EnvironmentObject private var store: TrackerStore
    let menuWeek: Int

    var body: some View {
        let plan = Plan.weeks[menuWeek]
        let counts = store.menuDoneCounts(week: menuWeek)

        VStack(alignment: .leading, spacing: 10) {
            Text("今週のメニュー").font(.subheadline.bold())
            ForEach(Array(doneFlags(plan: plan, counts: counts).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.done ? .green : Color(.systemGray4))
                    Text(item.label)
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? .secondary : .primary)
                    Spacer()
                }
                .font(.subheadline)
            }
            Text(plan.tip)
                .font(.caption)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.orange)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func doneFlags(plan: WeekPlan, counts: [String: Int]) -> [(label: String, done: Bool)] {
        var seen: [String: Int] = [:]
        return plan.runs.map { run in
            seen[run, default: 0] += 1
            return (run, counts[run, default: 0] >= seen[run]!)
        }
    }
}

// MARK: - 今日の食事

struct MealCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日の食事").font(.subheadline.bold())
                Spacer()
                Image(systemName: "fork.knife")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Meals.tips(on: Date()), id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(tip).font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - ヘルスケア連携

struct HealthCard: View {
    @EnvironmentObject private var store: TrackerStore
    @ObservedObject private var health = HealthKitManager.shared
    @State private var requesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: health.isEnabled ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(health.isAvailable ? .pink : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(healthTitle)
                        .font(.subheadline.bold())
                    Text(healthSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if health.isSyncing {
                    ProgressView()
                } else if health.isEnabled {
                    Button {
                        Task { await health.syncAll(into: store) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.bold())
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(.pink)
                } else if health.isAvailable {
                    Button("連携する") {
                        requesting = true
                        Task {
                            if await health.enable() {
                                await health.syncAll(into: store)
                            }
                            requesting = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(requesting)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                healthStatusRow(
                    icon: "clock",
                    text: health.lastSyncAt.map { "最終同期 \(syncTimeText($0))" } ?? "まだ同期していません",
                    color: .secondary
                )
                if let message = health.lastMessage {
                    healthStatusRow(
                        icon: health.lastMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        text: message,
                        color: health.lastMessageIsError ? .orange : .green
                    )
                } else if !health.isAvailable {
                    healthStatusRow(
                        icon: "exclamationmark.triangle.fill",
                        text: "この端末ではヘルスケアを利用できません",
                        color: .secondary
                    )
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var healthTitle: String {
        if !health.isAvailable { return "ヘルスケア非対応" }
        return health.isEnabled ? "ヘルスケア連携中" : "ヘルスケア連携"
    }

    private var healthSubtitle: String {
        if !health.isAvailable { return "この端末では自動記録を使えません" }
        return health.isEnabled
            ? "ワークアウトのランを自動でチェックイン"
            : "Apple Watch等で走った日を自動記録"
    }

    private func healthStatusRow(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func syncTimeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Plan.calendar
        f.dateFormat = Plan.calendar.isDateInToday(date) ? "今日 H:mm" : "M/d H:mm"
        return f.string(from: date)
    }
}

// MARK: - 統計

struct StatsCard: View {
    @EnvironmentObject private var store: TrackerStore

    var body: some View {
        HStack(spacing: 10) {
            stat(value: "\(store.streak(today: Date()))", label: "週連続達成")
            stat(value: "\(store.totalRuns)", label: "合計ラン")
            stat(value: Format.km(store.totalKm), label: "合計km")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 週カレンダー(岡山の18週 / レース後)

struct CalendarDaySelection: Identifiable {
    let date: Date
    var id: Date { date }
}

struct CalendarCard: View {
    @EnvironmentObject private var store: TrackerStore
    let title: String
    /// Plan.weekIndex の週番号。18以降はレース後の週
    let weeks: [Int]
    @State private var selectedDay: CalendarDaySelection?

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            Text("✓=走った ・=5分だけ 休=痛み休養 赤点=痛みあり").font(.caption2).foregroundStyle(.secondary)

            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("")
                    ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { d in
                        Text(d).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(weeks, id: \.self) { week in
                    GridRow {
                        Text(weekLabel(week))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 34)
                        ForEach(store.weekDates(week), id: \.self) { day in
                            Button {
                                selectedDay = CalendarDaySelection(date: day)
                            } label: {
                                dayCell(day)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(item: $selectedDay) { selection in
            DayLogEditor(date: selection.date)
                .environmentObject(store)
        }
    }

    /// プランの週は W1〜W18、レース後は週の月曜の日付
    private func weekLabel(_ week: Int) -> String { store.weekLabel(week) }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let log = store.runLog(on: day)
        let isToday = day == today
        // 岡山の本番と、次の目標の開催日に旗を立てる
        let isRace = day == Plan.race
            || store.nextGoal.map { Plan.calendar.isDate($0.date, inSameDayAs: day) } == true
        let dayNum = Plan.calendar.component(.day, from: day)

        let symbol: String = {
            switch log?.type {
            case .rest: return "休"
            case .mini: return "・"
            case .run: return "✓"
            case .strength, nil: return isRace ? "🏁" : " "
            }
        }()
        let symbolColor: Color = {
            switch log?.type {
            case .rest: return .blue
            case .mini: return .orange
            default: return .green
            }
        }()

        VStack(spacing: 0) {
            Text("\(dayNum)")
                .font(.caption2)
                .foregroundStyle(isToday ? .primary : .secondary)
            Text(symbol)
                .font(.caption2.bold())
                .foregroundStyle(symbolColor)
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(log != nil ? Color.green.opacity(0.15) : (isRace ? Color.orange.opacity(0.15) : Color(.systemGroupedBackground)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? Color.green : .clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if let pains = log?.pains, !pains.isEmpty {
                Circle().fill(.red).frame(width: 5, height: 5).padding(3)
            }
        }
    }
}

// MARK: - 日別記録編集

struct DayLogEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var logType: LogType = .run
    @State private var selectedMenu = ""
    @State private var kmText = ""
    @State private var selectedPains: Set<BodyPart> = []
    @State private var feel: Feel?
    @State private var errorMessage: String?
    @State private var loaded = false

    private var existingLog: RunLog? { store.log(on: date) }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Plan.calendar
        f.dateStyle = .full
        return f.string(from: date)
    }

    /// 既存の記録のメニューが選択肢に無い場合(ヘルスケアの自動記録など)も消えないように足す
    private var menuOptions: [String] {
        var options = store.menuOptions(on: date)
        if let menu = existingLog?.menu, !options.contains(menu) { options.insert(menu, at: 0) }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(dateLabel)
                }

                Section("記録") {
                    Picker("種類", selection: $logType) {
                        Text("走った").tag(LogType.run)
                        Text("5分だけ").tag(LogType.mini)
                        Text("痛み休養").tag(LogType.rest)
                    }
                    .pickerStyle(.segmented)
                }

                if logType == .run {
                    Section("ラン") {
                        Picker("メニュー", selection: $selectedMenu) {
                            ForEach(Array(menuOptions.enumerated()), id: \.offset) { _, option in
                                Text(option).tag(option)
                            }
                        }
                        TextField("距離 km 例: 6.5", text: $kmText)
                            .keyboardType(.decimalPad)
                    }
                }

                if logType != .rest {
                    Section("痛み") {
                        PainChips(selection: $selectedPains)
                    }

                    Section("調子") {
                        HStack(spacing: 8) {
                            ForEach(Feel.allCases, id: \.self) { f in
                                let selected = feel == f
                                Button {
                                    feel = selected ? nil : f
                                } label: {
                                    Text(f.label)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(selected ? Color.green.opacity(0.2) : Color(.systemGroupedBackground),
                                                    in: Capsule())
                                        .foregroundStyle(selected ? .green : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let existingLog, existingLog.type != .strength {
                    Section {
                        Button("この日の記録を削除", role: .destructive) {
                            store.removeRunRecord(on: date)
                            NotificationManager.reschedule(store: store)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingLog == nil ? "記録を追加" : "記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("入力エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: loadOnce)
        }
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true

        if let log = existingLog {
            logType = log.type == .strength ? .run : log.type
            selectedMenu = log.menu ?? store.defaultMenu(on: date)
            kmText = log.km.map(Format.km) ?? ""
            selectedPains = Set(log.pains ?? [])
            feel = log.feel
        } else {
            logType = .run
            selectedMenu = store.defaultMenu(on: date)
            kmText = ""
            selectedPains = []
            feel = nil
        }
    }

    private func save() {
        let km = parsedKm()
        if logType == .run && kmText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && km == nil {
            errorMessage = "距離は0以上の数値で入力してください"
            return
        }

        let pains = selectedPains.isEmpty ? nil : Array(selectedPains)
        switch logType {
        case .run:
            store.record(preservingHealthFields(RunLog(type: .run, menu: selectedMenu, km: km, pains: pains, feel: feel)), on: date)
        case .mini:
            store.record(preservingHealthFields(RunLog(type: .mini, pains: pains, feel: feel)), on: date)
        case .rest:
            store.record(preservingHealthFields(RunLog(type: .rest)), on: date)
        case .strength:
            // 筋トレは専用エディタで保存する。この画面の Picker からは選択されない。
            return
        }
        NotificationManager.reschedule(store: store)
        dismiss()
    }

    private func parsedKm() -> Double? {
        let text = kmText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func preservingHealthFields(_ log: RunLog) -> RunLog {
        guard let existing = existingLog else { return log }
        var next = log
        next.auto = existing.auto
        next.autoKm = existing.autoKm
        next.autoSeconds = existing.autoSeconds
        next.workoutIDs = existing.workoutIDs
        next.strength = existing.strength
        return next
    }
}

// MARK: - データ保管

struct DataBackupCard: View {
    @EnvironmentObject private var store: TrackerStore

    @State private var isExporting = false
    @State private var isImporting = false
    /// 同じビューに fileImporter を2つ付けると片方しか動かないので、1つを使い分ける
    @State private var importsHabitLife = false
    @State private var exportData = Data()
    @State private var exportFilename = "marathon-tracker-backup"
    @State private var pendingImportData: Data?
    @State private var pendingImportCount = 0
    @State private var showingImportConfirm = false
    @State private var statusText = ""
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("データ保管").font(.subheadline.bold())
            HStack(spacing: 8) {
                Button {
                    prepareExport()
                } label: {
                    Label("書き出す", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    importsHabitLife = false
                    isImporting = true
                } label: {
                    Label("読み込む", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                importsHabitLife = true
                isImporting = true
            } label: {
                Label("日々をつくるから取り込む", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text(statusText.isEmpty ? "記録は端末内に保存されています。機種変更前に書き出してください" : statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .fileExporter(
            isPresented: $isExporting,
            document: DataBackupDocument(data: exportData),
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                setStatus("バックアップを書き出しました")
            case .failure(let error):
                setStatus("書き出しに失敗しました: \(error.localizedDescription)", isError: true)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            if importsHabitLife {
                importHabitLife(result)
            } else {
                prepareImport(result)
            }
        }
        .alert("読み込み確認", isPresented: $showingImportConfirm) {
            Button("上書き", role: .destructive) {
                confirmImport()
            }
            Button("キャンセル", role: .cancel) {
                pendingImportData = nil
                setStatus("読み込みをキャンセルしました")
            }
        } message: {
            Text("現在の記録・次の目標・日々の記録を、読み込んだ\(pendingImportCount)件の記録で上書きします。")
        }
    }

    private func prepareExport() {
        do {
            exportData = try store.exportBackupData()
            exportFilename = "marathon-tracker-\(store.key(for: Date()))"
            isExporting = true
        } catch {
            setStatus("書き出しに失敗しました: \(error.localizedDescription)", isError: true)
        }
    }

    private func prepareImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let allowed = url.startAccessingSecurityScopedResource()
            defer {
                if allowed { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            pendingImportCount = try store.importPreviewCount(from: data)
            pendingImportData = data
            showingImportConfirm = true
        } catch {
            setStatus("読み込みに失敗しました: \(error.localizedDescription)", isError: true)
        }
    }

    /// Web版の書き出しは今の記録に足すだけなので、確認なしで取り込む
    private func importHabitLife(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let allowed = url.startAccessingSecurityScopedResource()
            defer {
                if allowed { url.stopAccessingSecurityScopedResource() }
            }
            let imported = try store.importHabitLife(Data(contentsOf: url))
            NotificationManager.reschedule(store: store)
            setStatus(imported.summary)
        } catch {
            setStatus("取り込みに失敗しました: \(error.localizedDescription)", isError: true)
        }
    }

    private func confirmImport() {
        guard let data = pendingImportData else { return }
        do {
            let count = try store.importBackupData(data)
            NotificationManager.reschedule(store: store)
            pendingImportData = nil
            setStatus("\(count)件の記録を読み込みました")
        } catch {
            setStatus("読み込みに失敗しました: \(error.localizedDescription)", isError: true)
        }
    }

    private func setStatus(_ text: String, isError: Bool = false) {
        statusText = text
        statusIsError = isError
    }

    private var statusColor: Color {
        if statusText.isEmpty { return .secondary }
        return statusIsError ? .red : .green
    }
}

#Preview {
    ContentView().environmentObject(TrackerStore())
}
