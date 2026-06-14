import SwiftUI

/// ③ 最近30天用量趋势 — 自绘柱状堆叠图：
/// 每天一根柱，柱内按模型降序自下而上堆叠，柱总高=当天总量；网格 + 悬停整柱高亮 tooltip（无图例，靠颜色与悬停区分）。
struct TrendChartView: View {
    let points: [TrendPoint]

    // MARK: 数据整形

    /// 按日期升序的 X 轴。
    private var days: [String] {
        Array(Set(points.map { $0.day })).sorted()
    }

    /// 各模型按总量降序（决定堆叠顺序与配色）。
    private var models: [String] {
        var totals: [String: Int] = [:]
        for p in points { totals[p.model, default: 0] += p.total }
        return totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { $0.key }
    }

    /// 一条堆叠分量：模型名、颜色、按 days 顺序的每日值。
    private struct Segment: Identifiable {
        let name: String
        let color: Color
        let values: [Int]
        var id: String { name }
    }

    /// 按降序模型构造堆叠分量（不含「总计」，柱总高即总量）。
    private var segments: [Segment] {
        let dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })
        var perModel: [String: [Int]] = [:]
        for m in models { perModel[m] = [Int](repeating: 0, count: days.count) }
        for p in points {
            guard let i = dayIndex[p.day] else { continue }
            perModel[p.model]?[i] += p.total
        }
        return models.enumerated().map { idx, m in
            Segment(name: m, color: UB.Palette.softSeriesColor(idx), values: perModel[m] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近30日趋势").font(UB.Font.sectionTitle)

            if days.isEmpty {
                Text("暂无数据").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 16)
            } else {
                StackedBarPlot(days: days, segments: segments.map { ($0.name, $0.color, $0.values) })
                    .frame(height: 180)
            }
        }
        .ubCard()
    }
}

/// 自绘柱状堆叠图：网格 + Y刻度 + 每日堆叠柱 + X日期 + 悬停整柱高亮 tooltip。
private struct StackedBarPlot: View {
    let days: [String]
    let segments: [(name: String, color: Color, values: [Int])]
    @State private var hoverIdx: Int?

    private let leading: CGFloat = 36
    private let trailing: CGFloat = 12
    private let topPad: CGFloat = 10
    private let bottomPad: CGFloat = 22
    private let yTicks = 3

    /// 每日总量（柱总高所依据）。
    private var dailyTotals: [Int] {
        (0..<days.count).map { i in segments.reduce(0) { $0 + ($1.values[safe: i] ?? 0) } }
    }
    private var maxValue: Int { max(dailyTotals.max() ?? 1, 1) }

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: leading, y: topPad,
                              width: max(geo.size.width - leading - trailing, 1),
                              height: max(geo.size.height - topPad - bottomPad, 1))

            ZStack(alignment: .topLeading) {
                gridLines(plot)
                yLabels(plot)
                xLabels(plot)
                bars(plot)
                if let hoverIdx { hoverOverlay(index: hoverIdx, plot: plot, size: geo.size) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hoverIdx = barIndex(at: loc.x, plot: plot)
                case .ended: hoverIdx = nil
                }
            }
        }
    }

    // MARK: 几何

    /// 第 i 根柱的中心 X。
    private func barCenter(_ i: Int, _ plot: CGRect) -> CGFloat {
        let slot = plot.width / CGFloat(days.count)
        return plot.minX + slot * (CGFloat(i) + 0.5)
    }
    /// 柱宽（占 slot 的 70%，封顶 16pt 避免太宽）。
    private func barWidth(_ plot: CGRect) -> CGFloat {
        let slot = plot.width / CGFloat(days.count)
        return min(max(slot * 0.7, 1), 16)
    }
    private func yPos(_ v: Int, _ plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * CGFloat(v) / CGFloat(maxValue)
    }

    private func barIndex(at x: CGFloat, plot: CGRect) -> Int? {
        guard days.count > 0, x >= plot.minX, x <= plot.maxX else { return nil }
        let slot = plot.width / CGFloat(days.count)
        let idx = Int((x - plot.minX) / slot)
        return min(max(idx, 0), days.count - 1)
    }

    // MARK: 绘制

    private func gridLines(_ plot: CGRect) -> some View {
        ForEach(0...yTicks, id: \.self) { i in
            let y = plot.minY + plot.height * CGFloat(i) / CGFloat(yTicks)
            Path { p in p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y)) }
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.6)
        }
    }

    private func yLabels(_ plot: CGRect) -> some View {
        ForEach(0...yTicks, id: \.self) { i in
            let v = maxValue * (yTicks - i) / yTicks
            let y = plot.minY + plot.height * CGFloat(i) / CGFloat(yTicks)
            Text(formatTokens(v)).font(.system(size: 9)).foregroundColor(.secondary).monospacedDigit()
                .frame(width: leading - 6, alignment: .trailing)
                .position(x: (leading - 6) / 2, y: y)
        }
    }

    private func xLabels(_ plot: CGRect) -> some View {
        // 最多标 5 个日期，避免拥挤
        let step = max(1, days.count / 5)
        return ForEach(Array(stride(from: 0, to: days.count, by: step)), id: \.self) { i in
            Text(shortDay(days[i])).font(.system(size: 9)).foregroundColor(.secondary)
                .position(x: barCenter(i, plot), y: plot.maxY + 12)
        }
    }

    /// 逐日堆叠柱：自下而上累加各模型段。
    private func bars(_ plot: CGRect) -> some View {
        let w = barWidth(plot)
        return ForEach(0..<days.count, id: \.self) { i in
            let cx = barCenter(i, plot)
            let highlighted = hoverIdx == i
            let total = dailyTotals[i]
            let yTop = yPos(total, plot)
            let barH = max(plot.maxY - yTop, 0)
            ZStack(alignment: .topLeading) {
                // 整柱色块：各段平铺后整体裁出顶部圆角（中间段缝隙保持直线，仅柱顶两角变圆）。
                ZStack(alignment: .topLeading) {
                    ForEach(segments.indices, id: \.self) { si in
                        let v = segments[si].values[safe: i] ?? 0
                        if v > 0 {
                            let base = segmentBase(upto: si, day: i)   // 此段下方累计值
                            let segTop = yPos(base + v, plot) - yTop    // 相对柱顶
                            let segBot = yPos(base, plot) - yTop
                            Rectangle()
                                .fill(segments[si].color.opacity(highlighted ? 1 : 0.85))
                                .frame(width: w, height: max(segBot - segTop, 0))
                                .position(x: w / 2, y: (segTop + segBot) / 2)
                        }
                    }
                }
                .frame(width: w, height: barH, alignment: .topLeading)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                .position(x: cx, y: yTop + barH / 2)

                // 高亮整柱描边（不参与裁剪）
                if highlighted {
                    UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                        .stroke(Color.primary.opacity(0.45), lineWidth: 1)
                        .frame(width: w + 2, height: barH + 2)
                        .position(x: cx, y: yTop + barH / 2)
                }
            }
        }
    }

    /// 第 si 段在第 day 天下方的累计值（即比它更靠下的段之和）。
    /// 堆叠顺序：降序模型（segments[0] 在最底）。
    private func segmentBase(upto si: Int, day: Int) -> Int {
        var sum = 0
        for k in 0..<si { sum += segments[k].values[safe: day] ?? 0 }
        return sum
    }

    private func hoverOverlay(index: Int, plot: CGRect, size: CGSize) -> some View {
        let cx = barCenter(index, plot)
        // 只列出当天有量的模型，降序已在 segments
        let rows = segments.compactMap { seg -> (String, Color, Int)? in
            let v = seg.values[safe: index] ?? 0
            return v > 0 ? (seg.name, seg.color, v) : nil
        }
        let total = dailyTotals[index]
        // 卡片宽度上限：图表可用宽度（两侧各留 8pt），既能容纳长模型名又不超出窗口。
        let tipMaxW = max(size.width - 16, 120)
        // 柱子偏右半则把卡片靠左摆，否则靠右摆（用容器对齐，无需预知卡片实宽）。
        let onLeft = cx > size.width / 2
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(days[index]).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    Spacer(minLength: 6)
                    Text(formatTokens(total)).font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white).monospacedDigit()
                }
                Divider().overlay(Color.white.opacity(0.25))
                ForEach(rows.indices, id: \.self) { ri in
                    HStack(alignment: .top, spacing: 5) {
                        Circle().fill(rows[ri].1).frame(width: 6, height: 6).padding(.top, 2)
                        // 不截断：自适应宽度，过长才换行（最多 2 行）。
                        Text(rows[ri].0).font(.system(size: 10)).foregroundColor(.white.opacity(0.85))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(formatTokens(rows[ri].2)).font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white).monospacedDigit()
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: tipMaxW, alignment: .leading)   // 上限封顶
            .fixedSize(horizontal: true, vertical: false)     // 未达上限时按内容收缩
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.82)))
        }
        .frame(width: max(plot.width, 1), alignment: onLeft ? .leading : .trailing)
        .position(x: plot.midX, y: plot.minY + 4 + 36)
    }

    private func shortDay(_ ymd: String) -> String {
        // "2026-06-14" -> "6/14"
        let parts = ymd.split(separator: "-")
        guard parts.count == 3 else { return ymd }
        return "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)"
    }
}

/// 安全下标，越界返回 nil。
private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

#Preview {
    var pts: [TrendPoint] = []
    let days = (1...20).map { String(format: "2026-06-%02d", $0) }
    for (i, d) in days.enumerated() {
        pts.append(TrendPoint(day: d, model: "claude-sonnet-4-6", total: 800_000 + i * 120_000))
        pts.append(TrendPoint(day: d, model: "deepseek-v4-pro", total: 400_000 + (i % 5) * 200_000))
        pts.append(TrendPoint(day: d, model: "claude-opus-4-8", total: 200_000 + (i % 3) * 90_000))
    }
    return TrendChartView(points: pts).padding().frame(width: 420)
}
