import SwiftUI

// MARK: - 振り返りタブ(週次レビュー)

struct WeeklyReviewView: View {
    @EnvironmentObject private var store: TrackerStore

    @State private var weekStart = TrackerStore.monday(of: Date())

    private var thisWeek: Date { TrackerStore.monday(of: Date()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                weekSwitcher
                SummaryCard(summary: store.weeklySummary(weekOf: weekStart))
                ReviewForm(weekStart: weekStart)
                    .id(store.key(for: weekStart))
                PastPriorities()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var weekSwitcher: some View {
        HStack {
            Button {
                weekStart = Plan.calendar.date(byAdding: .day, value: -7, to: weekStart)!
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("前の週")
            Spacer()
            VStack(spacing: 2) {
                Text("週の振り返り").font(.title2.bold())
                Text(rangeText).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                weekStart = Plan.calendar.date(byAdding: .day, value: 7, to: weekStart)!
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(weekStart >= thisWeek)
            .accessibilityLabel("次の週")
        }
        .padding(.top, 8)
    }

    private var rangeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Plan.calendar
        f.dateFormat = "M/d (E)"
        let end = Plan.calendar.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(f.string(from: weekStart)) 〜 \(f.string(from: end))"
    }
}

private struct SummaryCard: View {
    let summary: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("この週の記録").font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 12) {
                stat("記録した日", "\(summary.activeDays)/7")
                stat("ラン", String(format: "%.1fkm", summary.runKm), sub: "\(summary.runCount)回")
                stat("筋トレ", "\(summary.strengthCount)回")
                stat("食事", "\(summary.meals)回")
                stat("サプリ", "\(summary.supplements)回")
                stat("習慣", summary.habitTotal == 0 ? "—" : "\(summary.habitDone)/\(summary.habitTotal)")
                stat("平均睡眠", summary.averageSleep.map { String(format: "%.1f時間", $0) } ?? "—")
                stat("平均歩数", summary.averageSteps.map { "\($0)" } ?? "—")
                stat("30秒メモ", "\(summary.noteDays)日")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ label: String, _ value: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
            if let sub { Text(sub).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

private struct ReviewForm: View {
    @EnvironmentObject private var store: TrackerStore
    let weekStart: Date

    @State private var review = WeeklyReview(weekStart: "")
    @State private var loaded = false
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ふり返り").font(.subheadline.bold())
            field("うまくいったこと", $review.wins)
            field("学んだこと", $review.lessons)
            field("やめること", $review.stopDoing)
            field("来週の最優先", $review.nextPriority)
            HStack {
                Button("保存する", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                if saved {
                    Label("保存しました", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            review = store.weeklyReview(weekOf: weekStart) ?? WeeklyReview(weekStart: store.key(for: weekStart))
        }
        .alert("入力エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        do {
            try store.saveWeeklyReview(review)
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PastPriorities: View {
    @EnvironmentObject private var store: TrackerStore

    var body: some View {
        let past = store.weeklyReviews.values
            .filter { !$0.nextPriority.isEmpty }
            .sorted { $0.weekStart > $1.weekStart }
            .prefix(8)
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("これまでの「来週の最優先」").font(.subheadline.bold())
                ForEach(Array(past), id: \.weekStart) { review in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(review.weekStart.suffix(5)).replacingOccurrences(of: "-", with: "/"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(review.nextPriority).font(.caption)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
