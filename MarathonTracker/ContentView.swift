import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TrackerStore

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }
    private var currentWeek: Int { store.weekIndex(of: today) }
    private var menuWeek: Int { min(max(currentWeek, 0), Plan.weeks.count - 1) }
    private var inPlan: Bool { currentWeek >= 0 && currentWeek < Plan.weeks.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HeaderView(currentWeek: currentWeek, inPlan: inPlan)
                PainBanner()
                TodayCard(menuWeek: menuWeek)
                GaugeCard(currentWeek: currentWeek, menuWeek: menuWeek, inPlan: inPlan)
                MenuCard(menuWeek: menuWeek)
                MealCard()
                HealthCard()
                StatsCard()
                DistanceChartCard()
                CalendarCard()
                Text("目標: サブ4.5を確実に、10月の30km走の結果でサブ4を判断")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - ヘッダー

struct HeaderView: View {
    @EnvironmentObject private var store: TrackerStore
    let currentWeek: Int
    let inPlan: Bool

    private var daysToRace: Int {
        Plan.calendar.dateComponents([.day], from: Plan.calendar.startOfDay(for: Date()), to: Plan.race).day ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("おかやまマラソン 2026")
                    .font(.headline)
                Spacer()
                Text(Plan.phases[Plan.weeks[min(max(currentWeek, 0), Plan.weeks.count - 1)].phase])
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
                    Text("本番当日!")
                        .font(.system(size: 34, weight: .bold))
                } else {
                    Text("完走おめでとう 🎉")
                        .font(.system(size: 28, weight: .bold))
                }
                Spacer()
                Text(inPlan ? "第\(currentWeek + 1)週 / \(Plan.weeks.count)週" : (currentWeek < 0 ? "7/6(月)プラン開始" : "プラン終了"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                ForEach(Array(Plan.weeks.enumerated()), id: \.offset) { i, week in
                    Capsule()
                        .fill(phaseColor(week.phase))
                        .opacity(i <= currentWeek ? 1 : 0.25)
                        .frame(height: 6)
                }
            }
        }
        .padding(.top, 8)
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
    let menuWeek: Int

    @State private var showingForm = false
    @State private var selectedMenu = ""
    @State private var kmText = ""
    @State private var selectedPains: Set<BodyPart> = []
    @State private var feel: Feel?
    @State private var showingPainEditor = false

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }
    private var todayLog: RunLog? { store.log(on: today) }

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

            if let log = todayLog {
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
                Button("今日の記録を取り消す") {
                    store.remove(on: today)
                    NotificationManager.reschedule(store: store)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            } else if showingForm {
                VStack(alignment: .leading, spacing: 8) {
                    Text("どのメニュー?").font(.caption).foregroundStyle(.secondary)
                    Picker("メニュー", selection: $selectedMenu) {
                        ForEach(menuOptions, id: \.self) { Text($0).tag($0) }
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
                        store.record(RunLog(type: .mini, menu: nil, km: nil), on: today)
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
                        store.record(RunLog(type: .rest), on: today)
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

    private var menuOptions: [String] {
        var options = Plan.weeks[menuWeek].runs
        options.append("メニュー外の自由ラン")
        return options
    }

    private func prepareForm() {
        selectedMenu = store.nextMenu(on: today) ?? "メニュー外の自由ラン"
        kmText = ""
        selectedPains = []
        feel = nil
        showingForm = true
    }

    private func save() {
        let km = Double(kmText.replacingOccurrences(of: ",", with: "."))
        store.record(
            RunLog(type: .run, menu: selectedMenu, km: km,
                   pains: selectedPains.isEmpty ? nil : Array(selectedPains), feel: feel),
            on: today
        )
        NotificationManager.reschedule(store: store)
        showingForm = false
    }

    private func statusText(_ log: RunLog) -> String {
        if log.type == .rest { return "痛みで休んだ。正しい判断、今日も達成" }
        if log.type == .mini { return "5分だけでも走った。今日も勝ち" }
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
}

// MARK: - ゲージ

struct GaugeCard: View {
    @EnvironmentObject private var store: TrackerStore
    let currentWeek: Int
    let menuWeek: Int
    let inPlan: Bool

    var body: some View {
        let runCount = inPlan ? store.weekLogs(currentWeek).count : 0
        let km = inPlan ? store.weekKm(currentWeek) : 0
        let target = Plan.weeks[menuWeek].km

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
                    Text("\((km * 10).rounded() / 10, format: .number) / \(target, format: .number)km 目安")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(km / target, 1))
                    .tint(.blue)
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
        if health.isAvailable {
            HStack(spacing: 12) {
                Image(systemName: health.isEnabled ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(health.isEnabled ? "ヘルスケア連携中" : "ヘルスケア連携")
                        .font(.subheadline.bold())
                    Text(health.isEnabled
                         ? "ワークアウトのランを自動でチェックイン"
                         : "Apple Watch等で走った日を自動記録")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !health.isEnabled {
                    Button("連携する") {
                        requesting = true
                        Task {
                            if await health.enable() {
                                await health.syncWorkouts(into: store)
                            }
                            requesting = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(requesting)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
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

// MARK: - 18週間カレンダー

struct CalendarCard: View {
    @EnvironmentObject private var store: TrackerStore

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("18週間カレンダー").font(.subheadline.bold())
            Text("✓=走った ・=5分だけ 休=痛み休養 赤点=痛みあり").font(.caption2).foregroundStyle(.secondary)

            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("")
                    ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { d in
                        Text(d).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<Plan.weeks.count, id: \.self) { week in
                    GridRow {
                        Text("W\(week + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                        ForEach(store.weekDates(week), id: \.self) { day in
                            dayCell(day)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let log = store.log(on: day)
        let isToday = day == today
        let isRace = day == Plan.race
        let dayNum = Plan.calendar.component(.day, from: day)

        let symbol: String = {
            switch log?.type {
            case .rest: return "休"
            case .mini: return "・"
            case .run: return "✓"
            case nil: return isRace ? "🏁" : " "
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

#Preview {
    ContentView().environmentObject(TrackerStore())
}
