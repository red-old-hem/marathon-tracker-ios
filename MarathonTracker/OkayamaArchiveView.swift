import SwiftUI

// MARK: - 岡山マラソンの記録(レース後に見返す)

/// レース後のラン画面に置く入口。18週の集計を出し、タップで記録シートを開く
struct OkayamaArchiveCard: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingArchive = false

    var body: some View {
        let summary = store.planSummary
        Button {
            showingArchive = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "medal.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("岡山マラソン 2026 の記録").font(.subheadline.bold())
                    Text("18週で\(summary.runs)回・\(Format.km(summary.km))km・達成\(summary.achievedWeeks)週")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingArchive) {
            OkayamaArchiveView()
                .environmentObject(store)
        }
    }
}

struct OkayamaArchiveView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let summary = store.planSummary
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("2026/7/6 〜 11/8 の18週")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            stat("\(summary.runs)", "ラン")
                            stat(Format.km(summary.km), "km")
                            stat("\(summary.achievedWeeks)/\(Plan.weeks.count)", "達成週")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    DistanceChartCard()
                    CalendarCard(title: "18週間カレンダー", weeks: Array(0..<Plan.weeks.count))
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("岡山マラソン 2026")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
