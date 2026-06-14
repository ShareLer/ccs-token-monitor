import SwiftUI

/// ③ 最近30天用量趋势 — 自绘风格（参考 UsageBoard）：
/// 彩色指标卡图例（可点击只看单条）+ 平滑曲线 + 浅色面积填充 + 网格 + 悬停十字线 tooltip。
struct TrendChartView: View {
    let points: [TrendPoint]
    @State private var selected: String?      // 选中的 series 名（nil = 全部）

    // MARK: 数据整形

    /// 按日期升序的 X 轴。
    private var days: [String] {
        Array(Set(points.map { $0.day })).sorted()
    }

    /// 各模型按总量降序。
    private var models: [String] {
        var totals: [String: Int] = [:]
        for p in points { totals[p.model, default: 0] += p.total }
        return totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { $0.key }
    }

    /// 一条曲线：名称、颜色、按 days 顺序的值、总量。
    private struct Series: Identifiable {
        let name: String
        let color: Color
        let values: [Int]
        let total: Int
        var id: String { name }
    }

    private var allSeries: [Series] {
        // 「总计」线（蓝）+ 各模型线
        let dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1, $0) })
        var totalByDay = [Int](repeating: 0, count: days.count)
        var perModel: [String: [Int]] = [:]
        for m in models { perModel[m] = [Int](repeating: 0, count: days.count) }
        for p in points {
            guard let i = dayIndex[p.day] else { continue }
            totalByDay[i] += p.total
            perModel[p.model]?[i] += p.total
        }
        var out: [Series] = [Series(name: "总计", color: .blue, values: totalByDay, total: totalByDay.reduce(0,+))]
        for (idx, m) in models.enumerated() {
            let vals = perModel[m] ?? []
            out.append(Series(name: m, color: palette(idx), values: vals, total: vals.reduce(0,+)))
        }
        return out
    }

    /// 当前可见曲线（按图例选择过滤）。
    private var visibleSeries: [Series] {
        let nonEmpty = allSeries.filter { $0.values.contains { $0 > 0 } }
        guard let selected else { return nonEmpty }
        let only = nonEmpty.filter { $0.name == selected }
        return only.isEmpty ? nonEmpty : only
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近30天用量趋势").font(.system(size: 13, weight: .semibold))

            if days.isEmpty {
                Text("暂无数据").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 16)
            } else {
                legend
                LineChartPlot(days: days, series: visibleSeries.map { ($0.name, $0.color, $0.values) })
                    .frame(height: 170)
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
    }

    // MARK: 指标卡图例（可点击）

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  alignment: .leading, spacing: 8) {
            ForEach(allSeries.filter { $0.values.contains { $0 > 0 } }) { s in
                Button {
                    selected = (selected == s.name) ? nil : s.name
                } label: {
                    metricCard(s)
                }
                .buttonStyle(.plain)
                .help(selected == s.name ? "显示全部曲线" : "只看 \(s.name)")
            }
        }
    }

    private func metricCard(_ s: Series) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(s.color).frame(width: 7, height: 7)
                Text(s.name).font(.system(size: 11.5)).foregroundColor(.secondary).lineLimit(1)
            }
            Text(formatTokens(s.total))
                .font(.system(size: 16, weight: .bold)).monospacedDigit()
                .foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected == s.name ? s.color.opacity(0.12) : Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected == s.name ? s.color.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func palette(_ n: Int) -> Color {
        let base: [Color] = [.green, .orange, .purple, .pink, .teal, .red, .indigo, .mint, .brown, .cyan, .yellow]
        if n < base.count { return base[n] }
        let hue = Double((n - base.count) % 24) / 24.0
        return Color(hue: hue, saturation: 0.72, brightness: 0.78)
    }
}

/// 自绘折线图：网格 + Y刻度 + 平滑曲线 + 面积填充 + X日期 + 悬停十字线 tooltip。
private struct LineChartPlot: View {
    let days: [String]
    let series: [(name: String, color: Color, values: [Int])]
    @State private var hoverX: CGFloat?

    private let leading: CGFloat = 36
    private let trailing: CGFloat = 12
    private let topPad: CGFloat = 10
    private let bottomPad: CGFloat = 22
    private let yTicks = 3

    private var maxValue: Int {
        max(series.flatMap { $0.values }.max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: leading, y: topPad,
                              width: max(geo.size.width - leading - trailing, 1),
                              height: max(geo.size.height - topPad - bottomPad, 1))
            let hoverIdx = hoverIndex(in: plot)

            ZStack(alignment: .topLeading) {
                gridLines(plot)
                yLabels(plot)
                xLabels(plot)
                curves(plot)
                if let hoverIdx { hoverOverlay(index: hoverIdx, plot: plot, size: geo.size) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hoverX = loc.x
                case .ended: hoverX = nil
                }
            }
        }
    }

    private func xPos(_ i: Int, _ plot: CGRect) -> CGFloat {
        guard days.count > 1 else { return plot.midX }
        return plot.minX + plot.width * CGFloat(i) / CGFloat(days.count - 1)
    }
    private func yPos(_ v: Int, _ plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * CGFloat(v) / CGFloat(maxValue)
    }

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
                .position(x: xPos(i, plot), y: plot.maxY + 12)
        }
    }

    private func curves(_ plot: CGRect) -> some View {
        ZStack {
            ForEach(series.indices, id: \.self) { si in
                let s = series[si]
                let pts = s.values.indices.map { CGPoint(x: xPos($0, plot), y: yPos(s.values[$0], plot)) }
                if pts.count >= 2 {
                    // 面积填充
                    areaPath(pts, plot).fill(s.color.opacity(0.07))
                    // 平滑曲线
                    smoothPath(pts).stroke(s.color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                } else if pts.count == 1 {
                    Circle().fill(s.color).frame(width: 4, height: 4).position(pts[0])
                }
            }
        }
    }

    private func areaPath(_ pts: [CGPoint], _ plot: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: pts[0].x, y: plot.maxY))
            for pt in pts { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: pts.last!.x, y: plot.maxY))
            p.closeSubpath()
        }
    }

    /// Catmull-Rom 平滑曲线。
    private func smoothPath(_ pts: [CGPoint]) -> Path {
        Path { path in
            guard pts.count >= 2 else { return }
            path.move(to: pts[0])
            for i in 0..<pts.count - 1 {
                let p0 = i > 0 ? pts[i - 1] : pts[i]
                let p1 = pts[i]
                let p2 = pts[i + 1]
                let p3 = i + 2 < pts.count ? pts[i + 2] : p2
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
        }
    }

    private func hoverIndex(in plot: CGRect) -> Int? {
        guard let hoverX, days.count > 0 else { return nil }
        guard hoverX >= plot.minX - 10, hoverX <= plot.maxX + 10 else { return nil }
        let ratio = (hoverX - plot.minX) / plot.width
        let idx = Int((ratio * CGFloat(days.count - 1)).rounded())
        return min(max(idx, 0), days.count - 1)
    }

    private func hoverOverlay(index: Int, plot: CGRect, size: CGSize) -> some View {
        let x = xPos(index, plot)
        let rows = series.map { ($0.name, $0.color, $0.values[index]) }
        let tipW: CGFloat = 150
        // tooltip 放右侧，靠近右边界则放左侧
        let tipX = (x + tipW + 16 < size.width) ? x + 10 : x - tipW - 10
        return ZStack(alignment: .topLeading) {
            // 竖向虚线
            Path { p in p.move(to: CGPoint(x: x, y: plot.minY)); p.addLine(to: CGPoint(x: x, y: plot.maxY)) }
                .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            // 数据点
            ForEach(series.indices, id: \.self) { si in
                Circle().fill(series[si].color).frame(width: 5, height: 5)
                    .position(x: x, y: yPos(series[si].values[index], plot))
            }
            // tooltip
            VStack(alignment: .leading, spacing: 3) {
                Text(days[index]).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                ForEach(rows.indices, id: \.self) { ri in
                    HStack(spacing: 5) {
                        Circle().fill(rows[ri].1).frame(width: 6, height: 6)
                        Text(rows[ri].0).font(.system(size: 10)).foregroundColor(.white.opacity(0.85)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(formatTokens(rows[ri].2)).font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white).monospacedDigit()
                    }
                }
            }
            .padding(8)
            .frame(width: tipW, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.82)))
            .position(x: tipX + tipW / 2, y: plot.minY + 4 + 40)
        }
    }

    private func shortDay(_ ymd: String) -> String {
        // "2026-06-14" -> "6/14"
        let parts = ymd.split(separator: "-")
        guard parts.count == 3 else { return ymd }
        return "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)"
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
