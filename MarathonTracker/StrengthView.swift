import SwiftUI

// MARK: - 筋トレタブ(ランと分けて表示する。データは同じ日の RunLog.strength に保存)

struct StrengthView: View {
    @EnvironmentObject private var store: TrackerStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("筋トレ")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                StrengthCard()
                StrengthMenuCard()
                StrengthHistoryCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
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

struct StrengthMenuCard: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var editorTemplate: StrengthTemplate?
    @State private var confirmingStop = false

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }
    private var loggedToday: Bool { store.log(on: today)?.strength != nil }

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
        .sheet(item: $editorTemplate) { template in
            StrengthLogEditor(date: today, initialTemplate: template)
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

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    editorTemplate = store.strengthProgramTemplate(named: item.label, on: today)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? .green : Color(.systemGray4))
                        Text(item.label)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? .secondary : .primary)
                        Spacer()
                        if !item.done && !loggedToday {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.subheadline)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 今日すでに記録済みなら、上書きを避けて上の筋トレカードから編集してもらう
                .disabled(item.done || loggedToday)
                .accessibilityHint(item.done ? "消化済み" : "このメニューで今日の筋トレを記録")
            }

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

    @State private var category: StrengthCategory = .full
    @State private var templateName: String?
    @State private var exercises: [StrengthExercise] = []
    @State private var rpe = 0
    @State private var soreness: Set<SorenessArea> = []
    @State private var errorMessage: String?
    @State private var loaded = false

    init(date: Date, initialTemplate: StrengthTemplate? = nil) {
        self.date = date
        self.initialTemplate = initialTemplate
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("種目名", text: $exercises[index].name)
                                Button(role: .destructive) {
                                    exercises.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("\(exercises[index].name.isEmpty ? "種目" : exercises[index].name)を削除")
                            }
                            TextField("重量 kg（自重なら空欄）", text: weightBinding(for: index))
                                .keyboardType(.decimalPad)
                            HStack {
                                Stepper("\(exercises[index].sets)セット", value: $exercises[index].sets, in: 1...20)
                                Stepper("\(exercises[index].reps)回", value: $exercises[index].reps, in: 1...100)
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }

                    Menu {
                        ForEach(StrengthTemplate.machineGroups) { group in
                            Menu(group.name) {
                                ForEach(group.machines, id: \.self) { machine in
                                    Button(machine) {
                                        exercises.append(store.suggestedExercise(named: machine, on: date))
                                    }
                                }
                            }
                        }
                        Button("自由入力") {
                            exercises.append(StrengthExercise(name: "", reps: 10, sets: 3))
                        }
                    } label: {
                        Label("種目を追加", systemImage: "plus")
                    }
                }

                Section("主観的負荷") {
                    Picker("RPE", selection: $rpe) {
                        Text("未記録").tag(0)
                        ForEach(1...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
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
            category = existingStrength.category
            templateName = existingStrength.templateName
            exercises = existingStrength.exercises
            rpe = existingStrength.rpe ?? 0
            soreness = Set(existingStrength.soreness ?? [])
        } else if let initialTemplate {
            apply(initialTemplate)
        }
    }

    private func apply(_ template: StrengthTemplate) {
        category = template.category
        templateName = template.name
        exercises = template.exercises.map { store.withLastWeight($0, on: date) }
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
