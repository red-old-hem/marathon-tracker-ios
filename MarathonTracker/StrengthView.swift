import SwiftUI

// MARK: - 筋トレタブ(ランと分けて表示する。データは同じ日の RunLog.strength に保存)

struct StrengthView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var selectedDay = Plan.calendar.startOfDay(for: Date())

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("筋トレ").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
                StrengthWeekStrip(selectedDay: $selectedDay)
                StrengthDailyCard(day: selectedDay)
                StrengthMenuCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct StrengthWeekStrip: View {
    @EnvironmentObject private var store: TrackerStore
    @Binding var selectedDay: Date

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }
    private var monday: Date { TrackerStore.monday(of: selectedDay) }
    private let weekdays = ["月", "火", "水", "木", "金", "土", "日"]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("前の週")
                Spacer()
                Text(monday.formatted(.dateTime.year().month().day()) + " の週")
                    .font(.subheadline.bold())
                Spacer()
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(Plan.calendar.date(byAdding: .day, value: 7, to: monday)! > today)
                    .accessibilityLabel("次の週")
            }
            .buttonStyle(.borderless)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = Plan.calendar.date(byAdding: .day, value: offset, to: monday)!
                    Button {
                        selectedDay = day
                    } label: {
                        VStack(spacing: 4) {
                            Text(weekdays[offset]).font(.caption2)
                            Text(day.formatted(.dateTime.day())).font(.subheadline.bold())
                            Circle().fill(store.log(on: day)?.strength == nil ? Color.clear : Color.teal)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Plan.calendar.isDate(day, inSameDayAs: selectedDay) ? Color.teal.opacity(0.16) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(day > today)
                    .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted) + (store.log(on: day)?.strength == nil ? "" : " 筋トレ記録あり"))
                }
            }
            DatePicker("別の日へ", selection: $selectedDay, in: ...today, displayedComponents: .date)
                .font(.caption)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func moveWeek(_ direction: Int) {
        let next = Plan.calendar.date(byAdding: .day, value: direction * 7, to: selectedDay)!
        selectedDay = min(next, today)
    }
}

struct StrengthDailyCard: View {
    @EnvironmentObject private var store: TrackerStore
    let day: Date
    @State private var showingEditor = false
    @State private var copyPrevious = false

    private var strength: StrengthLog? { store.log(on: day)?.strength }
    private var previous: StrengthLog? { store.previousStrength(before: day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.formatted(.dateTime.month().day().weekday(.wide))).font(.headline)
                Spacer()
                if let strength {
                    Text(strength.category.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let strength {
                if let name = strength.templateName {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(strength.exercises.indices, id: \.self) { index in
                    let exercise = strength.exercises[index]
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercise.name).font(.subheadline)
                        Spacer(minLength: 6)
                        Text(exercise.weightKg.map { "\(Format.km($0))kg" } ?? "自重")
                        Text("\(exercise.reps)回 × \(exercise.sets)")
                    }
                    .font(.caption.monospacedDigit())
                    if index < strength.exercises.count - 1 { Divider() }
                }
                if let rpe = strength.rpe {
                    Text("きつさ RPE \(rpe)").font(.caption).foregroundStyle(.secondary)
                }
                Button("この日の記録を編集") {
                    copyPrevious = false
                    showingEditor = true
                }
                .buttonStyle(.bordered)
            } else {
                Text("この日の筋トレはまだ記録されていません")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("この日に行った筋トレを記録") {
                    copyPrevious = false
                    showingEditor = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                if previous != nil {
                    Button("前回と同じ内容から始める") {
                        copyPrevious = true
                        showingEditor = true
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showingEditor) {
            StrengthLogEditor(date: day, initialStrength: copyPrevious ? previous : nil)
                .environmentObject(store)
        }
    }
}

/// 最近の筋トレと、過去の日の記録・編集(ランのカレンダーから外した入口)
struct StrengthHistoryCard: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var editing: CalendarDaySelection?
    @State private var pastDay = Plan.calendar.date(byAdding: .day, value: -1, to: Plan.calendar.startOfDay(for: Date()))!

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近の筋トレ").font(.subheadline.bold())
            let recent = store.recentStrengthDays()
            if recent.isEmpty {
                Text("まだ記録がありません").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(recent, id: \.self) { day in
                if let strength = store.log(on: day)?.strength {
                    Button {
                        editing = CalendarDaySelection(date: day)
                    } label: {
                        HStack {
                            Text(dayLabel(day)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(strength.templateName ?? strength.category.label).font(.subheadline)
                            Spacer()
                            Text("\(strength.exercises.count)種目").font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                DatePicker("過去の日", selection: $pastDay, in: ...today, displayedComponents: .date)
                    .font(.subheadline)
                Button("記録") { editing = CalendarDaySelection(date: Plan.calendar.startOfDay(for: pastDay)) }
                    .buttonStyle(.bordered)
                    .tint(.teal)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(item: $editing) { selection in
            StrengthLogEditor(date: selection.date)
                .environmentObject(store)
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Plan.calendar
        f.dateFormat = "M/d (E)"
        return f.string(from: day)
    }
}

struct StrengthCard: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingEditor = false
    @State private var initialTemplate: StrengthTemplate?

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }
    private var strength: StrengthLog? { store.log(on: today)?.strength }
    private var suggestion: StrengthSuggestion { store.strengthSuggestion(on: today) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title3)
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("筋トレ")
                        .font(.subheadline.bold())
                    Text(strength == nil ? "種目・重量・主観的負荷を記録" : strengthSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    initialTemplate = nil
                    showingEditor = true
                } label: {
                    Image(systemName: strength == nil ? "plus" : "pencil")
                        .font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
                .accessibilityLabel(strength == nil ? "筋トレを記録" : "筋トレを編集")
            }

            if let strength {
                Text(strength.exercises.map(exerciseSummary).joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if strength.rpe != nil || !(strength.soreness ?? []).isEmpty {
                    HStack(spacing: 8) {
                        if let rpe = strength.rpe {
                            Label("RPE \(rpe)", systemImage: "gauge.with.dots.needle.33percent")
                        }
                        if let soreness = strength.soreness, !soreness.isEmpty {
                            Label(soreness.map(\.label).joined(separator: "・"), systemImage: "bolt.heart")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } else {
                suggestionView
            }
            Text("累計 \(store.totalStrengthSessions)回")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showingEditor) {
            StrengthLogEditor(date: today, initialTemplate: initialTemplate)
                .environmentObject(store)
        }
    }

    private var strengthSummary: String {
        guard let strength else { return "" }
        return "\(strength.templateName ?? strength.category.label) / \(strength.exercises.count)種目"
    }

    private func exerciseSummary(_ exercise: StrengthExercise) -> String {
        var result = exercise.name
        if let weight = exercise.weightKg { result += " \(Format.km(weight))kg" }
        return "\(result) \(exercise.sets)セット×\(exercise.reps)回"
    }

    @ViewBuilder
    private var suggestionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.template == nil ? "heart.text.square" : "sparkles")
                    .foregroundStyle(suggestion.template == nil ? .orange : .teal)
                Text(suggestion.title)
                    .font(.caption.bold())
            }
            if let template = suggestion.template {
                Text(template.name)
                    .font(.subheadline.bold())
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    initialTemplate = template
                    showingEditor = true
                } label: {
                    Label("このメニューを使う", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
            } else {
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 筋トレメニュー

private struct StrengthMenuDraft: Identifiable {
    let id = UUID()
    let log: StrengthLog
}

struct StrengthMenuCard: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var editorDraft: StrengthMenuDraft?
    @State private var selectedExercises: [String: Set<Int>] = [:]
    @State private var confirmingStop = false

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let week = store.strengthProgramWeek(of: today) {
                if StrengthProgram.weeks.indices.contains(week) {
                    activeView(week: week)
                } else if week < 0 {
                    upcomingView
                } else {
                    finishedView
                }
            } else {
                notStartedView
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(item: $editorDraft, onDismiss: { selectedExercises.removeAll() }) { draft in
            StrengthLogEditor(date: today, initialStrength: draft.log, mergeInitialStrength: true)
                .environmentObject(store)
        }
        .confirmationDialog("筋トレプログラムをやめますか？", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("やめる", role: .destructive) { store.stopStrengthProgram() }
        } message: {
            Text("これまでの筋トレ記録は残ります")
        }
    }

    private func activeView(week: Int) -> some View {
        let plan = StrengthProgram.weeks[week]
        let items = doneFlags(plan: plan, counts: store.strengthMenuDoneCounts(week: week))
        let doneCount = items.filter(\.done).count

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今週の筋トレメニュー").font(.subheadline.bold())
                Spacer()
                Text("第\(week + 1)週 / \(StrengthProgram.weeks.count)週・\(StrengthProgram.phases[plan.phase])")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Menu {
                    Button("プログラムをやめる", role: .destructive) { confirmingStop = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("筋トレプログラムの操作")
            }

            HStack {
                Label(plan.volume.label, systemImage: "dumbbell")
                    .foregroundStyle(.teal)
                Spacer()
                Text("\(doneCount) / \(items.count)回\(doneCount == items.count ? " 完了!" : "")")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            ForEach(Array(items.enumerated()), id: \.offset) { sessionIndex, item in
                if let template = store.preparedStrengthTemplate(named: item.label, on: today) {
                    let selectionKey = "\(week):\(sessionIndex)"
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? .green : Color(.systemGray4))
                            Text(item.label)
                                .font(.subheadline.bold())
                            if item.done {
                                Text("記録済み").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(template.exercises.indices, id: \.self) { index in
                            let exercise = template.exercises[index]
                            let selected = selectedExercises[selectionKey, default: []].contains(index)
                            let recorded = store.log(on: today)?.strength?.exercises.contains { $0.name == exercise.name } == true
                            Button {
                                if selected {
                                    selectedExercises[selectionKey, default: []].remove(index)
                                } else {
                                    selectedExercises[selectionKey, default: []].insert(index)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selected ? .teal : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.name)
                                        Text("\(exercise.weightKg.map { "目安 \(Format.km($0))kg" } ?? "重量は当日設定") · \(exercise.reps)回×\(exercise.sets)セット")
                                            .foregroundStyle(.secondary)
                                        if recorded {
                                            Text("今日の記録にあり")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .font(.caption)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(item.done)
                            .accessibilityLabel("\(exercise.name)を\(selected ? "選択解除" : "選択")\(recorded ? "、今日の記録にあり" : "")")
                        }
                        if !item.done, let selected = selectedExercises[selectionKey], !selected.isEmpty {
                            Button {
                                let chosen = template.exercises.indices.filter { selected.contains($0) }
                                    .map { template.exercises[$0] }
                                let log = StrengthLog(category: template.category,
                                                      templateName: chosen.count == template.exercises.count ? template.name : nil,
                                                      exercises: chosen)
                                editorDraft = StrengthMenuDraft(log: log)
                            } label: {
                                Label("選んだ\(selected.count)種目を今日の記録へ", systemImage: "square.and.pencil")
                            }
                            .buttonStyle(.bordered)
                            .tint(.teal)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("実際に行った種目を選び、重量・回数を確認して保存すると当日の記録になります")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("重量は同じマシンの前回記録から表示。記録がなければ当日決めてください")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(plan.tip)
                .font(.caption)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.teal)
        }
    }

    private var notStartedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("筋トレメニュー").font(.subheadline.bold())
            Text("基礎期・強化期・維持期の\(StrengthProgram.weeks.count)週プログラム。週2〜3回のマシンメニューを、期に合わせたセット・回数で進めます")
                .font(.caption)
                .foregroundStyle(.secondary)
            startButton("今週から始める")
        }
    }

    private var upcomingView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("筋トレメニュー").font(.subheadline.bold())
            if let start = store.strengthProgramStart {
                Text("\(start.formatted(.dateTime.month().day()))の週から開始します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var finishedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(StrengthProgram.weeks.count)週プログラム完了 🎉").font(.subheadline.bold())
            Text("累計 \(store.totalStrengthSessions)回。記録した重量を出発点に、もう一周できます")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                startButton("もう一度始める")
                Button("終了する") { store.stopStrengthProgram() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func startButton(_ title: String) -> some View {
        Button {
            store.startStrengthProgram(on: today)
        } label: {
            Label(title, systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)
    }

    private func doneFlags(plan: StrengthWeekPlan, counts: [String: Int]) -> [(label: String, done: Bool)] {
        var seen: [String: Int] = [:]
        return plan.sessions.map { name in
            seen[name, default: 0] += 1
            return (name, counts[name, default: 0] >= seen[name]!)
        }
    }
}

// MARK: - 筋トレの記録・編集

struct SorenessChips: View {
    @Binding var selection: Set<SorenessArea>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(SorenessArea.allCases) { area in
                let selected = selection.contains(area)
                Button {
                    if selected { selection.remove(area) } else { selection.insert(area) }
                } label: {
                    Text(area.label)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Color.orange.opacity(0.15) : Color(.systemGroupedBackground),
                                    in: Capsule())
                        .foregroundStyle(selected ? .orange : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StrengthLogEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let initialTemplate: StrengthTemplate?
    let initialStrength: StrengthLog?
    let mergeInitialStrength: Bool

    @State private var expandedExercise: Int?
    @State private var category: StrengthCategory = .full
    @State private var templateName: String?
    @State private var exercises: [StrengthExercise] = []
    @State private var rpe = 0
    @State private var soreness: Set<SorenessArea> = []
    @State private var errorMessage: String?
    @State private var loaded = false

    init(date: Date, initialTemplate: StrengthTemplate? = nil, initialStrength: StrengthLog? = nil,
         mergeInitialStrength: Bool = false) {
        self.date = date
        self.initialTemplate = initialTemplate
        self.initialStrength = initialStrength
        self.mergeInitialStrength = mergeInitialStrength
    }

    private var existingStrength: StrengthLog? { store.log(on: date)?.strength }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Plan.calendar
        f.dateStyle = .full
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(dateLabel)
                }

                Section("内容") {
                    Picker("部位", selection: $category) {
                        ForEach(StrengthCategory.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }

                    Menu {
                        ForEach(StrengthTemplate.presets) { template in
                            Button(template.name) {
                                apply(store.strengthProgramTemplate(named: template.name, on: date) ?? template)
                            }
                        }
                    } label: {
                        Label(templateName ?? "テンプレートを適用", systemImage: "square.on.square")
                    }
                }

                Section("種目") {
                    ForEach(exercises.indices, id: \.self) { index in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedExercise == index },
                            set: { expandedExercise = $0 ? index : nil }
                        )) {
                            HStack {
                                TextField("種目名", text: $exercises[index].name)
                                Button(role: .destructive) {
                                    exercises.remove(at: index)
                                    expandedExercise = nil
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("種目を削除")
                            }
                            HStack {
                                TextField("重量 kg（自重なら空欄）", text: weightBinding(for: index))
                                    .keyboardType(.decimalPad)
                                Button("−2.5") { adjustWeight(at: index, by: -2.5) }
                                    .buttonStyle(.bordered)
                                Button("+2.5") { adjustWeight(at: index, by: 2.5) }
                                    .buttonStyle(.bordered)
                            }
                            Stepper("\(exercises[index].sets)セット", value: $exercises[index].sets, in: 1...20)
                            Stepper("\(exercises[index].reps)回", value: $exercises[index].reps, in: 1...100)
                        } label: {
                            HStack {
                                Text(exercises[index].name.isEmpty ? "新しい種目" : exercises[index].name)
                                Spacer()
                                Text("\(exercises[index].weightKg.map { Format.km($0) + "kg" } ?? "自重") · \(exercises[index].reps)回×\(exercises[index].sets)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Menu {
                        ForEach(StrengthTemplate.machineGroups) { group in
                            Menu(group.name) {
                                ForEach(group.machines, id: \.self) { machine in
                                    Button(machine) {
                                        exercises.append(store.suggestedExercise(named: machine, on: date))
                                        expandedExercise = exercises.count - 1
                                    }
                                }
                            }
                        }
                        Button("自由入力") {
                            exercises.append(StrengthExercise(name: "", reps: 10, sets: 3))
                            expandedExercise = exercises.count - 1
                        }
                    } label: {
                        Label("種目を追加", systemImage: "plus")
                    }
                }

                Section("主観的負荷") {
                    HStack(spacing: 4) {
                        ForEach(Array([("楽", 2), ("ふつう", 5), ("ややきつい", 7), ("きつい", 8), ("限界", 10)].enumerated()), id: \.offset) { _, option in
                            Button(option.0) { rpe = option.1 }
                                .font(.caption2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(rpeRange(rpe) == rpeRange(option.1) && rpe != 0 ? Color.teal.opacity(0.18) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityAddTraits(rpeRange(rpe) == rpeRange(option.1) && rpe != 0 ? .isSelected : [])
                        }
                    }
                    .buttonStyle(.plain)
                    Button("きつさを未記録にする") { rpe = 0 }
                        .font(.caption)
                        .disabled(rpe == 0)
                    Text(rpe == 0 ? "主観的なきつさを残せます" : "RPE \(rpe): \(rpeDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("筋肉痛・張り") {
                    SorenessChips(selection: $soreness)
                }

                if existingStrength != nil {
                    Section {
                        Button("筋トレ記録を削除", role: .destructive) {
                            store.removeStrength(on: date)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingStrength == nil ? "筋トレを記録" : "筋トレを編集")
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

    private var rpeDescription: String {
        switch rpe {
        case 1...3: return "余裕あり"
        case 4...6: return "適度"
        case 7...8: return "きつい"
        default: return "限界に近い"
        }
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        if let existingStrength {
            let draft = mergeInitialStrength && initialStrength != nil
                ? existingStrength.addingRecommendedExercises(initialStrength!) : existingStrength
            category = draft.category
            templateName = draft.templateName
            exercises = draft.exercises
            rpe = draft.rpe ?? 0
            soreness = Set(draft.soreness ?? [])
        } else if let initialStrength {
            category = initialStrength.category
            templateName = initialStrength.templateName
            exercises = initialStrength.exercises
            rpe = 0
            soreness = []
        } else if let initialTemplate {
            apply(initialTemplate)
        }
    }

    private func apply(_ template: StrengthTemplate) {
        category = template.category
        templateName = template.name
        exercises = template.exercises.map { store.withLastWeight($0, on: date) }
    }

    private func rpeRange(_ value: Int) -> Int {
        switch value {
        case 1...3: return 1
        case 4...6: return 2
        case 7: return 3
        case 8...9: return 4
        case 10: return 5
        default: return 0
        }
    }

    private func adjustWeight(at index: Int, by delta: Double) {
        let current = exercises[index].weightKg ?? 0
        exercises[index].weightKg = max(0, current + delta)
    }

    private func weightBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { exercises[index].weightKg.map(Format.km) ?? "" },
            set: { text in
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: ".")
                exercises[index].weightKg = Double(normalized)
            }
        )
    }

    private func save() {
        let normalizedExercises = exercises.map { exercise in
            StrengthExercise(
                name: exercise.name.trimmingCharacters(in: .whitespacesAndNewlines),
                weightKg: exercise.weightKg,
                reps: exercise.reps,
                sets: exercise.sets
            )
        }
        guard !normalizedExercises.isEmpty else {
            errorMessage = "種目を1つ以上追加してください"
            return
        }
        guard normalizedExercises.allSatisfy({ !$0.name.isEmpty && $0.weightKg.map({ $0.isFinite && $0 >= 0 }) != false }) else {
            errorMessage = "種目名と重量を確認してください"
            return
        }

        store.recordStrength(
            StrengthLog(
                category: category,
                templateName: templateName,
                exercises: normalizedExercises,
                rpe: rpe == 0 ? nil : rpe,
                soreness: soreness.isEmpty ? nil : Array(soreness)
            ),
            on: date
        )
        dismiss()
    }
}
