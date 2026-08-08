import SwiftUI
import Charts

// MARK: - 週別の走行距離

struct DistanceChartCard: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var selectedX: String?

    private var currentWeek: Int {
        store.weekIndex(of: Plan.calendar.startOfDay(for: Date()))
    }
    private var stats: [WeekStat] { store.weekStats }
    private var selected: WeekStat? {
        guard let x = selectedX else { return nil }
        return stats.first { $0.label == x }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("週別の走行距離").font(.subheadline.bold())
                Spacer()
                Text("累計 \(Format.km(store.totalKm))km")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 高さを固定してタップ時にレイアウトが跳ねないようにする
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 16, alignment: .leading)

            // x はカテゴリカル(週ラベル)。数値軸だと .ratio 幅が解決されず棒が描画されない
            Chart {
                ForEach(stats) { stat in
                    BarMark(
                        x: .value("週", stat.label),
                        y: .value("実績", stat.actualKm),
                        width: .ratio(0.68)
                    )
                    .foregroundStyle(phaseColor(stat.phase).opacity(stat.week == currentWeek ? 1 : 0.7))
                    .cornerRadius(2)
                }

                ForEach(stats) { stat in
                    LineMark(
                        x: .value("週", stat.label),
                        y: .value("目標", stat.targetKm),
                        series: .value("系列", "target")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.stepCenter)
                }

                if let selected {
                    RuleMark(x: .value("週", selected.label))
                        .foregroundStyle(Color.primary.opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .zIndex(-1)
                }
            }
            .chartXSelection(value: $selectedX)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: ["W1", "W6", "W12", "W18"]) { value in
                    AxisValueLabel {
                        if let w = value.as(String.self) {
                            // fixedSize がないと右端の W18 が "..." に切り詰められる
                            Text(w).font(.caption2).fixedSize()
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 165)

            // chartXSelection は横ドラッグで反応する(縦ドラッグは ScrollView に流れる)。
            // タップでは選択されないので「なぞる」と案内する
            Text("棒=実績(色はフェーズ) / 破線=目標。横になぞると週ごとの詳細")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// 目標ペースは参照値として併記するだけで、達成判定には使わない。
    /// イージーラン中心のプランでは平均が常に目標より遅くなるため。
    private var detailText: String {
        if let s = selected {
            var text = "\(s.label)  \(Format.km(s.actualKm)) / \(Format.km(s.targetKm))km"
            if let pace = s.paceSecPerKm { text += "  \(Format.pace(pace))" }
            return text
        }
        if let pace = store.averagePaceSecPerKm {
            return "平均ペース \(Format.pace(pace))  (サブ4.5=6:24, サブ4=5:41)"
        }
        return "サブ4.5 = 6:24/km, サブ4 = 5:41/km"
    }
}

#Preview {
    let store = TrackerStore()
    for w in 0..<8 {
        for d in [1, 3, 5] {
            let day = Plan.calendar.date(byAdding: .day, value: w * 7 + d, to: Plan.start)!
            store.record(
                RunLog(type: .run, menu: Plan.weeks[w].runs[0],
                       autoKm: Double.random(in: 4...12),
                       autoSeconds: Int.random(in: 1800...5400)),
                on: day
            )
        }
    }
    return ScrollView { DistanceChartCard().padding(16) }
        .background(Color(.systemGroupedBackground))
        .environmentObject(store)
}
