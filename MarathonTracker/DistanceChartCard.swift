import SwiftUI
import Charts

// MARK: - 週別の走行距離

struct DistanceChartCard: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var selectedX: String?

    /// 表示する週(古い順)。既定は岡山の18週。レース後の週には目標距離がない
    var weeks: [Int] = Array(0..<Plan.weeks.count)

    private var isPlan: Bool { weeks.allSatisfy { $0 < Plan.weeks.count } }

    /// 目安距離がある週(岡山の18週か、次の目標のプラン期間)
    private func hasTarget(_ week: Int) -> Bool {
        isPlan || store.weekPlan(of: week) != nil
    }

    private var currentWeek: Int {
        store.weekIndex(of: Plan.calendar.startOfDay(for: Date()))
    }
    private var stats: [WeekStat] { weeks.map { store.stat(week: $0) } }
    private var selected: WeekStat? {
        guard let x = selectedX else { return nil }
        return stats.first { store.weekLabel($0.week) == x }
    }

    /// 横軸のラベルは先頭・1/3・2/3・末尾の4つだけ出す(全部出すと重なる)
    private var axisLabels: [String] {
        guard !weeks.isEmpty else { return [] }
        let last = weeks.count - 1
        let picks = [0, last / 3, last * 2 / 3, last]
        var seen = Set<Int>()
        return picks.filter { seen.insert($0).inserted }.map { store.weekLabel(weeks[$0]) }
    }

    /// 18週は岡山の累計、レース後は表示した週の合計
    private var totalText: String {
        if isPlan { return "累計 \(Format.km(store.planSummary.km))km" }
        let km = stats.map(\.actualKm).reduce(0, +)
        return "合計 \(Format.km((km * 10).rounded() / 10))km"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("週別の走行距離").font(.subheadline.bold())
                Spacer()
                Text(totalText)
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
                        x: .value("週", store.weekLabel(stat.week)),
                        y: .value("実績", stat.actualKm),
                        width: .ratio(0.68)
                    )
                    // プラン外のレース後の週はフェーズがないので1色
                    .foregroundStyle((hasTarget(stat.week) ? phaseColor(stat.phase) : Color.teal)
                        .opacity(stat.week == currentWeek ? 1 : 0.7))
                    .cornerRadius(2)
                }

                // 岡山の18週と、次の目標のプラン期間の週だけ目標線を引く
                ForEach(stats.filter { hasTarget($0.week) }) { stat in
                    LineMark(
                        x: .value("週", store.weekLabel(stat.week)),
                        y: .value("目標", stat.targetKm),
                        series: .value("系列", "target")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.stepCenter)
                }

                if let selected {
                    RuleMark(x: .value("週", store.weekLabel(selected.week)))
                        .foregroundStyle(Color.primary.opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .zIndex(-1)
                }
            }
            .chartXSelection(value: $selectedX)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: axisLabels) { value in
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
            Text(isPlan ? "棒=実績(色はフェーズ) / 破線=目標。横になぞると週ごとの詳細"
                 : stats.contains(where: { hasTarget($0.week) })
                    ? "横軸は週の月曜日。破線=次の目標のプランの目安。横になぞると週ごとの詳細"
                    : "横軸は週の月曜日。横になぞると週ごとの詳細")
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
            let label = store.weekLabel(s.week)
            var text = hasTarget(s.week) ? "\(label)  \(Format.km(s.actualKm)) / \(Format.km(s.targetKm))km"
                                         : "\(label)の週  \(Format.km(s.actualKm))km"
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
