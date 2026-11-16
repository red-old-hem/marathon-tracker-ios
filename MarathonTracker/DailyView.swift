import SwiftUI

// MARK: - 今日タブ(日々をつくるから統合した毎日の記録)

struct DailyView: View {
    @EnvironmentObject private var store: TrackerStore

    private var today: Date { Plan.calendar.startOfDay(for: Date()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DailyHeader(today: today)
                WorkNoteCard(today: today)
                HabitsCard(today: today)
                EntriesCard(today: today)
                MetricCard(today: today)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private extension View {
    /// 既存カード(ContentView.swift)と同じ見た目
    func dailyCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    func inputErrorAlert(_ message: Binding<String?>) -> some View {
        alert("入力エラー", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

private func dayText(_ date: Date, format: String = "M月d日 (E)") -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.calendar = Plan.calendar
    f.dateFormat = format
    return f.string(from: date)
}

struct DailyHeader: View {
    @EnvironmentObject private var store: TrackerStore
    let today: Date

    private var done: [Bool] {
        var items = [store.workNote(on: today) != nil, !store.entries(on: today).isEmpty, store.metric(on: today) != nil]
        let habits = store.activeHabits
        if !habits.isEmpty {
            items.append(habits.allSatisfy { store.habitCheck(habitId: $0.id, on: today) != nil })
        }
        return items
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayText(today)).font(.subheadline).foregroundStyle(.secondary)
                Text("今日の記録").font(.title2.bold())
            }
            Spacer()
            Text("\(done.filter { $0 }.count)/\(done.count) 完了")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.15), in: Capsule())
                .foregroundStyle(.blue)
        }
        .padding(.top, 8)
    }
}

// MARK: - 30秒メモ

struct WorkNoteCard: View {
    @EnvironmentObject private var store: TrackerStore
    let today: Date

    @State private var fun = ""
    @State private var drain = ""
    @State private var loadedDay = ""
    @State private var errorMessage: String?
    @State private var saved = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日の30秒メモ").font(.subheadline.bold())
                Spacer()
                Image(systemName: "pencil.line").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("一語でいい。たまると、仕事の何が合っていて何が合わないかが見えてくる。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("○ 少し面白かった作業", text: $fun)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            TextField("△ 消耗した作業", text: $drain)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack {
                Button(store.workNote(on: today) == nil ? "保存する" : "書き直す", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                if saved {
                    Label("保存しました", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            let recent = store.recentWorkNotes().filter { $0.day != store.key(for: today) }
            if !recent.isEmpty {
                Divider()
                ForEach(recent.prefix(5), id: \.day) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(note.day.suffix(5)).replacingOccurrences(of: "-", with: "/"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            if !note.fun.isEmpty { Text("○ \(note.fun)").font(.caption) }
                            if !note.drain.isEmpty { Text("△ \(note.drain)").font(.caption) }
                        }
                    }
                }
            }
        }
        .dailyCard()
        .onAppear(perform: load)
        .onChange(of: today) { _, _ in load() }
        .inputErrorAlert($errorMessage)
    }

    private func load() {
        let day = store.key(for: today)
        guard loadedDay != day else { return }
        loadedDay = day
        fun = store.workNote(on: today)?.fun ?? ""
        drain = store.workNote(on: today)?.drain ?? ""
        saved = false
    }

    private func save() {
        do {
            try store.saveWorkNote(fun: fun, drain: drain, on: today)
            focused = false
            saved = true
            NotificationManager.reschedule(store: store)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 習慣

struct HabitsCard: View {
    @EnvironmentObject private var store: TrackerStore
    let today: Date

    @State private var checking: Habit?
    @State private var editing: Habit?
    @State private var showingManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("習慣").font(.subheadline.bold())
                Spacer()
                Button {
                    showingManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("習慣を管理")
            }
            if store.activeHabits.isEmpty {
                Text("続けたい行動を1つ登録しよう。できない日用の「最小版」も決めておくと続きやすい。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("習慣を追加") { editing = Habit(id: TrackerStore.newID(), title: "") }
                    .buttonStyle(.bordered)
            }
            ForEach(store.activeHabits) { habit in
                HabitRow(habit: habit, check: store.habitCheck(habitId: habit.id, on: today)) {
                    quickDone(habit)
                } onOpen: {
                    checking = habit
                }
            }
        }
        .dailyCard()
        .sheet(item: $checking) { habit in
            HabitCheckEditor(habit: habit, day: today)
                .environmentObject(store)
        }
        .sheet(item: $editing) { habit in
            HabitEditor(habit: habit)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingManager) {
            HabitManager()
                .environmentObject(store)
        }
    }

    /// ひと言が要らなければ1タップで「できた」。要るならシートで入力してもらう
    private func quickDone(_ habit: Habit) {
        if store.habitCheck(habitId: habit.id, on: today) != nil {
            checking = habit
        } else if habit.requiresDetail(for: .done) {
            checking = habit
        } else {
            try? store.checkHabit(id: habit.id, status: .done, on: today)
        }
    }
}

struct HabitRow: View {
    let habit: Habit
    let check: HabitCheck?
    let onQuick: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onQuick) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(check == nil ? "\(habit.title)をできたにする" : "\(habit.title)の記録を変更")
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.title).font(.subheadline).foregroundStyle(.primary)
                    if let check {
                        Text(check.detail.isEmpty ? check.status.label : "\(check.status.label)・\(check.detail)")
                            .font(.caption)
                            .foregroundStyle(color)
                    } else if !habit.minimum.isEmpty {
                        Text("最小版: \(habit.minimum)").font(.caption).foregroundStyle(.secondary)
                    } else if !habit.cue.isEmpty {
                        Text(habit.cue).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var icon: String {
        switch check?.status {
        case .done: return "checkmark.circle.fill"
        case .small: return "circle.lefthalf.filled"
        case .partial: return "circle.dotted"
        case .skip: return "minus.circle"
        case nil: return "circle"
        }
    }

    private var color: Color {
        switch check?.status {
        case .done, .small: return .green
        case .partial: return .orange
        case .skip: return .secondary
        case nil: return .secondary
        }
    }
}

struct HabitCheckEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    let day: Date

    @State private var status: HabitStatus = .done
    @State private var detail = ""
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("今日は", selection: $status) {
                        ForEach(HabitStatus.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if !habit.minimum.isEmpty {
                        Text("最小版: \(habit.minimum)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField(habit.requiresDetail(for: status) ? "ひと言(必須)" : "ひと言(任意)", text: $detail)
                } footer: {
                    Text("強制力: \(habit.enforcement.label)")
                }
                if store.habitCheck(habitId: habit.id, on: day) != nil {
                    Section {
                        Button("今日の記録を取り消す", role: .destructive) {
                            store.clearHabitCheck(id: habit.id, on: day)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(habit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
            .inputErrorAlert($errorMessage)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let check = store.habitCheck(habitId: habit.id, on: day) {
                    status = check.status
                    detail = check.detail
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        do {
            try store.checkHabit(id: habit.id, status: status, detail: detail, on: day)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct HabitEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("習慣") {
                    TextField("例: 寝る前にストレッチ", text: $habit.title)
                    TextField("きっかけ(任意・例: 歯みがきの後)", text: $habit.cue)
                    TextField("最小版(任意・例: 1種目だけ)", text: $habit.minimum)
                }
                Section {
                    Picker("強制力", selection: $habit.enforcement) {
                        ForEach(HabitEnforcement.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("標準は「一部」「見送り」のとき、強いは毎回ひと言の記録が必要です。")
                }
                if store.habits[habit.id] != nil {
                    Section {
                        Button(habit.archived ? "再開する" : "休止する") {
                            store.setHabitArchived(id: habit.id, !habit.archived)
                            dismiss()
                        }
                        Button("削除(記録も消えます)", role: .destructive) {
                            store.deleteHabit(id: habit.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(store.habits[habit.id] == nil ? "習慣を追加" : "習慣を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try store.saveHabit(habit)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .inputErrorAlert($errorMessage)
        }
    }
}

struct HabitManager: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Habit?

    var body: some View {
        NavigationStack {
            List {
                Section("続けている習慣") {
                    ForEach(store.activeHabits) { habit in
                        Button(habit.title) { editing = habit }
                    }
                    Button {
                        editing = Habit(id: TrackerStore.newID(), title: "")
                    } label: {
                        Label("習慣を追加", systemImage: "plus")
                    }
                }
                if !store.archivedHabits.isEmpty {
                    Section("休止中") {
                        ForEach(store.archivedHabits) { habit in
                            Button(habit.title) { editing = habit }
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("習慣を管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .sheet(item: $editing) { habit in
                HabitEditor(habit: habit)
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - 食事・サプリ

struct EntriesCard: View {
    @EnvironmentObject private var store: TrackerStore
    let today: Date

    @State private var adding: DailyEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("食事・サプリ").font(.subheadline.bold())
                Spacer()
                Menu {
                    Button("食事を記録") { adding = newEntry(.meal) }
                    Button("サプリを記録") { adding = newEntry(.supplement) }
                } label: {
                    Label("記録", systemImage: "plus.circle.fill")
                }
            }

            let usuals = store.usualEntries()
            if !usuals.isEmpty {
                Text("いつもの").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(usuals) { entry in
                            Button {
                                store.repeatEntry(entry)
                            } label: {
                                HStack(spacing: 4) {
                                    if entry.isFavorite { Image(systemName: "star.fill").font(.caption2) }
                                    Text(entry.title).lineLimit(1)
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(entry.kind == .meal ? .orange : .purple)
                        }
                    }
                }
            }

            let entries = store.entries(on: today)
            if entries.isEmpty {
                Text("まだ記録がありません").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.kind.label)・\(entry.title)").font(.subheadline)
                        if !entry.detail.isEmpty {
                            Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Menu {
                        Button(entry.isFavorite ? "お気に入りを外す" : "お気に入りにする") {
                            store.toggleFavorite(id: entry.id)
                        }
                        Button("編集") { adding = entry }
                        Button("削除", role: .destructive) { store.removeEntry(id: entry.id) }
                    } label: {
                        Image(systemName: entry.isFavorite ? "star.fill" : "ellipsis")
                            .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("\(entry.title)の操作")
                }
            }
        }
        .dailyCard()
        .sheet(item: $adding) { entry in
            EntryEditor(entry: entry)
                .environmentObject(store)
        }
    }

    private func newEntry(_ kind: EntryKind) -> DailyEntry {
        DailyEntry(id: TrackerStore.newID(), day: store.key(for: today),
                   time: TrackerStore.timeString(Date()), kind: kind, title: "")
    }
}

struct EntryEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: DailyEntry
    @State private var time = Date()
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("種類", selection: $entry.kind) {
                        Text(EntryKind.meal.label).tag(EntryKind.meal)
                        Text(EntryKind.supplement.label).tag(EntryKind.supplement)
                        if entry.kind == .exercise { Text(EntryKind.exercise.label).tag(EntryKind.exercise) }
                    }
                    .pickerStyle(.segmented)
                    TextField(entry.kind == .supplement ? "例: ビタミンD" : "例: 鮭定食", text: $entry.title)
                    DatePicker("時刻", selection: $time, displayedComponents: .hourAndMinute)
                }
                if entry.kind == .meal {
                    Section("食品群") {
                        ForEach(MealGroup.all, id: \.self) { group in
                            Toggle(group, isOn: Binding(
                                get: { entry.groups.contains(group) },
                                set: { on in
                                    entry.groups.removeAll { $0 == group }
                                    if on { entry.groups.append(group) }
                                    entry.groups.sort { MealGroup.all.firstIndex(of: $0)! < MealGroup.all.firstIndex(of: $1)! }
                                }
                            ))
                        }
                    }
                }
                Section {
                    HStack {
                        TextField("量(任意)", text: $entry.amount)
                            .keyboardType(.decimalPad)
                        TextField("単位", text: $entry.unit)
                            .frame(width: 80)
                    }
                    TextField("メモ(任意)", text: $entry.note, axis: .vertical)
                }
            }
            .navigationTitle(store.dailyEntries[entry.id] == nil ? "\(entry.kind.label)を記録" : "記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
            .inputErrorAlert($errorMessage)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let parts = entry.time.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2, let date = store.dailyDate(entry.day) {
                    time = Plan.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date) ?? Date()
                }
            }
        }
    }

    private func save() {
        entry.time = TrackerStore.timeString(time)
        do {
            try store.addEntry(entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 体調

struct MetricCard: View {
    @EnvironmentObject private var store: TrackerStore
    let today: Date

    @State private var editing = false

    /// 気分 1〜5 の顔
    private static let moods = [1: "😞", 2: "🙁", 3: "😐", 4: "🙂", 5: "😄"]

    var body: some View {
        let metric = store.metric(on: today)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("体調").font(.subheadline.bold())
                Spacer()
                Button("入力") { editing = true }.font(.subheadline)
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        try? store.saveMetric(weightKg: metric?.weightKg, sleepHours: metric?.sleepHours,
                                              mood: metric?.mood == value ? nil : value, on: today)
                    } label: {
                        Text(Self.moods[value] ?? "")
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(metric?.mood == value ? Color.blue.opacity(0.2) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("気分 \(value)")
                }
            }
            HStack(spacing: 16) {
                value("体重", metric?.weight.map { String(format: "%.1fkg", $0) }, auto: metric?.weightKg == nil)
                value("睡眠", metric?.sleep.map { String(format: "%.1f時間", $0) }, auto: metric?.sleepHours == nil)
                value("歩数", metric?.steps.map { "\($0)歩" }, auto: true)
            }
        }
        .dailyCard()
        .sheet(isPresented: $editing) {
            MetricEditor(day: today)
                .environmentObject(store)
        }
    }

    private func value(_ label: String, _ text: String?, auto: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text ?? "—").font(.subheadline.monospacedDigit())
            if text != nil, auto {
                Text("ヘルスケア").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct MetricEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let day: Date

    @State private var weight = ""
    @State private var sleep = ""
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("体重(kg)", text: $weight).keyboardType(.decimalPad)
                    TextField("睡眠(時間)", text: $sleep).keyboardType(.decimalPad)
                } footer: {
                    Text("空欄にするとヘルスケアの値を使います。")
                }
            }
            .navigationTitle(dayText(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
            .inputErrorAlert($errorMessage)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let metric = store.metric(on: day)
                weight = metric?.weightKg.map { String(format: "%g", $0) } ?? ""
                sleep = metric?.sleepHours.map { String(format: "%g", $0) } ?? ""
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        do {
            let weightValue = try parse(weight, "体重")
            let sleepValue = try parse(sleep, "睡眠")
            try store.saveMetric(weightKg: weightValue, sleepHours: sleepValue,
                                 mood: store.metric(on: day)?.mood, on: day)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parse(_ text: String, _ name: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty { return nil }
        guard let value = Double(trimmed) else { throw DailyInputError.invalidValue(name) }
        return value
    }
}
