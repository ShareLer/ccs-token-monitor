import SwiftUI

/// ③ 最近30天用量趋势：支持自绘堆叠柱状图 / 折线图。
struct TrendChartView: View {
    let points: [TrendPoint]
    var displayMode: TrendChartDisplayMode = .bar

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
                switch displayMode {
                case .bar:
                    StackedBarPlot(days: days, segments: segments.map { ($0.name, $0.color, $0.values) })
                        .frame(height: 180)
                case .line:
                    LineTrendPlot(days: days, series: lineSeries)
                        .frame(height: 180)
                }
            }
        }
        .ubCard()
    }

    private var lineSeries: [(name: String, color: Color, values: [Int])] {
        let modelSeries = segments.map { ($0.name, $0.color, $0.values) }
        let totalValues = (0..<days.count).map { i in
            segments.reduce(0) { $0 + ($1.values[safe: i] ?? 0) }
        }
        return modelSeries + [(name: "总计", color: UB.Palette.accent, values: totalValues)]
    }
}

/// 自绘柱状堆叠图：网格 + Y刻度 + 每日堆叠柱 + X日期 + 悬停整柱高亮 tooltip。
private struct StackedBarPlot: View {
    let days: [String]
    let segments: [(name: String, color: Color, values: [Int])]
    @State private var hoverIdx: Int?
    @Environment(\.colorScheme) private var colorScheme

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
                .stroke(
                    UB.Canvas.lineColor(.grid, for: colorScheme),
                    lineWidth: UB.Canvas.lineWidth(.grid, for: colorScheme)
                )
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
            Text(shortTrendDay(days[i])).font(.system(size: 9)).foregroundColor(.secondary)
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
}

/// 自绘折线图：网格 + Y刻度 + 每模型连续折线 + X日期 + 悬停 tooltip。无图例。
private struct LineTrendPlot: View {
    let days: [String]
    let series: [(name: String, color: Color, values: [Int])]
    @State private var hoverIdx: Int?
    @Environment(\.colorScheme) private var colorScheme

    private let leading: CGFloat = 36
    private let trailing: CGFloat = 12
    private let topPad: CGFloat = 10
    private let bottomPad: CGFloat = 22
    private let yTicks = 3
    private let maxTooltipModelRows = 6

    private struct TooltipRow {
        let name: String
        let color: Color
        let value: Int
    }

    private var maxValue: Int {
        max(series.flatMap { $0.values }.max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: leading, y: topPad,
                              width: max(geo.size.width - leading - trailing, 1),
                              height: max(geo.size.height - topPad - bottomPad, 1))

            ZStack(alignment: .topLeading) {
                gridLines(plot)
                yLabels(plot)
                xLabels(plot)
                lines(plot)
                if let hoverIdx { hoverOverlay(index: hoverIdx, plot: plot, size: geo.size) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hoverIdx = nearestDay(at: loc.x, plot: plot)
                case .ended: hoverIdx = nil
                }
            }
        }
    }

    private func xPos(_ i: Int, _ plot: CGRect) -> CGFloat {
        guard days.count > 1 else { return plot.midX }
        return plot.minX + CGFloat(i) / CGFloat(days.count - 1) * plot.width
    }

    private func yPos(_ v: Int, _ plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * CGFloat(v) / CGFloat(maxValue)
    }

    private func nearestDay(at x: CGFloat, plot: CGRect) -> Int? {
        guard !days.isEmpty, x >= plot.minX, x <= plot.maxX else { return nil }
        guard days.count > 1 else { return 0 }
        let ratio = min(max((x - plot.minX) / plot.width, 0), 1)
        return min(max(Int((ratio * CGFloat(days.count - 1)).rounded()), 0), days.count - 1)
    }

    private func gridLines(_ plot: CGRect) -> some View {
        ForEach(0...yTicks, id: \.self) { i in
            let y = plot.minY + plot.height * CGFloat(i) / CGFloat(yTicks)
            Path { p in p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y)) }
                .stroke(
                    UB.Canvas.lineColor(.grid, for: colorScheme),
                    lineWidth: UB.Canvas.lineWidth(.grid, for: colorScheme)
                )
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
        let step = max(1, days.count / 5)
        return ForEach(Array(stride(from: 0, to: days.count, by: step)), id: \.self) { i in
            Text(shortTrendDay(days[i])).font(.system(size: 9)).foregroundColor(.secondary)
                .position(x: xPos(i, plot), y: plot.maxY + 12)
        }
    }

    private func lines(_ plot: CGRect) -> some View {
        ZStack {
            ForEach(series.indices, id: \.self) { si in
                let points = series[si].values.indices.map { i in
                    CGPoint(x: xPos(i, plot), y: yPos(series[si].values[i], plot))
                }

                if points.count >= 2 {
                    if series[si].name != "总计" {
                        fillPath(points: points, plot: plot)
                            .fill(series[si].color.opacity(0.06))
                    }
                    smoothPath(points: points)
                        .stroke(
                            series[si].color,
                            style: StrokeStyle(
                                lineWidth: series[si].name == "总计" ? 2.2 : 1.5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                } else if points.count == 1 {
                    Circle()
                        .fill(series[si].color)
                        .frame(width: 4, height: 4)
                        .position(points[0])
                }
            }
        }
    }

    private func hoverOverlay(index: Int, plot: CGRect, size: CGSize) -> some View {
        let x = xPos(index, plot)
        let modelSeries: [(name: String, color: Color, values: [Int])]
        let totalValue: Int
        let totalColor: Color
        if let last = series.last, last.name == "总计" {
            modelSeries = Array(series.dropLast())
            totalValue = last.values[safe: index] ?? 0
            totalColor = last.color
        } else {
            modelSeries = series
            totalValue = series.reduce(0) { $0 + ($1.values[safe: index] ?? 0) }
            totalColor = UB.Palette.accent
        }
        var modelRows: [TooltipRow] = []
        for item in modelSeries {
            let value = item.values[safe: index] ?? 0
            if value > 0 {
                modelRows.append(TooltipRow(name: item.name, color: item.color, value: value))
            }
        }
        modelRows.sort { lhs, rhs in
            lhs.value == rhs.value ? lhs.name < rhs.name : lhs.value > rhs.value
        }
        let visibleRows = Array(modelRows.prefix(maxTooltipModelRows))
        let hiddenRows = modelRows.dropFirst(maxTooltipModelRows)
        let hiddenTotal = hiddenRows.reduce(0) { $0 + $1.value }
        let tipMaxW = max(size.width - 16, 120)
        let onLeft = x > size.width / 2
        return ZStack(alignment: .topLeading) {
            Path { p in p.move(to: CGPoint(x: x, y: plot.minY)); p.addLine(to: CGPoint(x: x, y: plot.maxY)) }
                .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            ForEach(series.indices, id: \.self) { si in
                let value = series[si].values[safe: index] ?? 0
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .background(Circle().fill(series[si].color))
                    .frame(width: 6, height: 6)
                    .opacity(series[si].name == "总计" ? 1 : 0.75)
                    .position(x: x, y: yPos(value, plot))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(days[index]).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                Divider().overlay(Color.white.opacity(0.25))
                HStack(alignment: .top, spacing: 5) {
                    Circle().fill(totalColor).frame(width: 6, height: 6).padding(.top, 2)
                    Text("总计").font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                    Spacer(minLength: 8)
                    Text(formatTokens(totalValue)).font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white).monospacedDigit()
                }
                if visibleRows.isEmpty {
                    Text("无模型用量").font(.system(size: 10)).foregroundColor(.white.opacity(0.65))
                } else {
                    Divider().overlay(Color.white.opacity(0.16))
                }
                ForEach(visibleRows.indices, id: \.self) { ri in
                    HStack(alignment: .top, spacing: 5) {
                        Circle().fill(visibleRows[ri].color).frame(width: 6, height: 6).padding(.top, 2)
                        Text(visibleRows[ri].name).font(.system(size: 10)).foregroundColor(.white.opacity(0.85))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(formatTokens(visibleRows[ri].value)).font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white).monospacedDigit()
                    }
                }
                if !hiddenRows.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Circle().fill(Color.white.opacity(0.45)).frame(width: 6, height: 6).padding(.top, 2)
                        Text("其他 \(hiddenRows.count) 个模型").font(.system(size: 10)).foregroundColor(.white.opacity(0.75))
                        Spacer(minLength: 8)
                        Text(formatTokens(hiddenTotal)).font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white).monospacedDigit()
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: tipMaxW, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.82)))
            .frame(width: max(plot.width, 1), alignment: onLeft ? .leading : .trailing)
            .position(x: plot.midX, y: plot.minY + 76)
        }
    }

    private func fillPath(points: [CGPoint], plot: CGRect) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: plot.maxY))
            for point in points {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: plot.maxY))
            path.closeSubpath()
        }
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        Path { path in
            guard points.count >= 2 else {
                if points.count == 1 {
                    path.move(to: points[0])
                    path.addLine(to: points[0])
                }
                return
            }
            path.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                let prevPrev = i >= 2 ? points[i - 2] : prev
                let next = i + 1 < points.count ? points[i + 1] : curr
                let cp1 = CGPoint(
                    x: prev.x + (curr.x - prevPrev.x) / 6,
                    y: prev.y + (curr.y - prevPrev.y) / 6
                )
                let cp2 = CGPoint(
                    x: curr.x - (next.x - prev.x) / 6,
                    y: curr.y - (next.y - prev.y) / 6
                )
                let minY = min(prev.y, curr.y)
                let maxY = max(prev.y, curr.y)
                let clampedCP1 = CGPoint(x: cp1.x, y: min(max(cp1.y, minY), maxY))
                let clampedCP2 = CGPoint(x: cp2.x, y: min(max(cp2.y, minY), maxY))
                path.addCurve(to: curr, control1: clampedCP1, control2: clampedCP2)
            }
        }
    }
}

private func shortTrendDay(_ ymd: String) -> String {
    let parts = ymd.split(separator: "-")
    guard parts.count == 3 else { return ymd }
    return "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)"
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
    return TrendChartView(points: pts, displayMode: .line).padding().frame(width: 420)
}
