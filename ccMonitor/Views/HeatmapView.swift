import SwiftUI

/// ④ Token 活动热力图（本自然年，7 行 × N 列）。
/// fit 模式：动态缩放格子完全显示不滑动；scroll 模式：固定格子可横向滑动。
struct HeatmapView: View {
    let days: [HeatmapDay]
    var fitMode: HeatmapFitMode = .fit
    @Environment(\.colorScheme) private var colorScheme

    private let gap: CGFloat = 3
    private let scrollCell: CGFloat = 11   // scroll 模式固定格子边长

    /// 鼠标即时悬停的格子（自绘 tooltip，替代有延迟的系统 .help）。
    @State private var hover: HoverInfo?

    private struct HoverInfo: Equatable {
        let date: Date
        let total: Int
    }

    private var totalByDay: [String: Int] {
        let f = Self.dayFormatter
        return Dictionary(days.map { (f.string(from: $0.date), $0.total) }, uniquingKeysWith: +)
    }
    private var maxTotal: Int { days.map { $0.total }.max() ?? 0 }

    /// 本自然年的周列：从「今年1月1日所在周的周日」到「今天所在周的周日」。
    private var grid: [[Date]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yearStart = cal.date(from: cal.dateComponents([.year], from: today))!
        // 各自回退到所在周的周日（weekday: 1=周日）
        let startSunday = cal.date(byAdding: .day,
                                   value: -(cal.component(.weekday, from: yearStart) - 1),
                                   to: yearStart)!
        let lastSunday = cal.date(byAdding: .day,
                                  value: -(cal.component(.weekday, from: today) - 1),
                                  to: today)!
        let weeks = (cal.dateComponents([.day], from: startSunday, to: lastSunday).day! / 7) + 1
        var cols: [[Date]] = []
        for w in 0..<weeks {
            let colStart = cal.date(byAdding: .day, value: w * 7, to: startSunday)!
            cols.append((0..<7).map { cal.date(byAdding: .day, value: $0, to: colStart)! })
        }
        return cols
    }

    private func level(_ total: Int) -> Int {
        guard total > 0, maxTotal > 0 else { return 0 }
        let r = Double(total) / Double(maxTotal)
        if r > 0.66 { return 4 }
        if r > 0.33 { return 3 }
        if r > 0.1 { return 2 }
        return 1
    }

    private func color(_ lvl: Int) -> Color {
        heatmapPalette[min(max(lvl, 0), heatmapPalette.count - 1)]
    }

    private var heatmapPalette: [Color] {
        if colorScheme == .dark {
            return [
                Color(hex: 0x202833),
                Color(hex: 0x173B36),
                Color(hex: 0x1E6B57),
                Color(hex: 0x2FA36F),
                Color(hex: 0x7DE08B),
            ]
        }
        return [
            Color(hex: 0xE0E0E0),
            Color(hex: 0xD6E685),
            Color(hex: 0x8CC665),
            Color(hex: 0x44A340),
            Color(hex: 0x1E6823),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token热力图").font(UB.Font.sectionTitle)
                Spacer()
                // 鼠标滑过格子即时显示（无系统 .help 延迟）
                if let hover {
                    Text("\(Self.dayFormatter.string(from: hover.date))  \(formatTokens(hover.total))")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            if fitMode == .fit {
                // 用 GeometryReader 拿可用宽度，动态算格子边长铺满不滑动
                GeometryReader { geo in
                    let cols = grid.count
                    let cell = max(2, (geo.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols))
                    gridBody(cell: cell)
                }
                .frame(height: 7 * fitCellEstimate() + 6 * gap + 16)  // 7 行 + 月份标签预留
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    gridBody(cell: scrollCell)
                }
            }
        }
        .ubCard()
    }

    /// fit 模式高度估算：用 420 面板宽减 padding 估算单格高度。
    private func fitCellEstimate() -> CGFloat {
        let cols = max(1, grid.count)
        let usable: CGFloat = 420 - 16 * 2   // 面板宽 - 左右 padding
        return max(2, (usable - gap * CGFloat(cols - 1)) / CGFloat(cols))
    }

    private func gridBody(cell: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, col in
                    VStack(spacing: gap) {
                        ForEach(Array(col.enumerated()), id: \.offset) { _, day in
                            let key = Self.dayFormatter.string(from: day)
                            RoundedRectangle(cornerRadius: max(1, cell * 0.18))
                                .fill(color(level(totalByDay[key] ?? 0)))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            // 鼠标滑过即时更新（网格自身坐标系内反算格子，顶部即时显示，无 .help 延迟）
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hover = hitTest(loc, cell: cell)
                case .ended: hover = nil
                }
            }
            monthLabels(cell: cell)
        }
    }

    /// 鼠标坐标 → 格子。超出格子区域返回 nil。
    private func hitTest(_ loc: CGPoint, cell: CGFloat) -> HoverInfo? {
        let step = cell + gap
        let col = Int(loc.x / step)
        let row = Int(loc.y / step)
        guard col >= 0, col < grid.count, row >= 0, row < grid[col].count else { return nil }
        // 落在格子之间的 gap 上则忽略
        guard loc.x - CGFloat(col) * step <= cell, loc.y - CGFloat(row) * step <= cell else { return nil }
        let date = grid[col][row]
        let key = Self.dayFormatter.string(from: date)
        return HoverInfo(date: date, total: totalByDay[key] ?? 0)
    }

    /// 月份标签：每列首日是月初（≤7号）时标出月份。
    private func monthLabels(cell: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, col in
                let first = col.first!
                let cal = Calendar.current
                let dayNum = cal.component(.day, from: first)
                Text(dayNum <= 7 ? Self.monthFormatter.string(from: first) : "")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .frame(width: cell)
                    .fixedSize()
            }
        }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f
    }()
    static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M月"; f.timeZone = .current; return f
    }()
}

#Preview {
    let cal = Calendar.current
    var days: [HeatmapDay] = []
    let yearStart = cal.date(from: cal.dateComponents([.year], from: Date()))!
    var d = yearStart
    while d <= Date() {
        days.append(HeatmapDay(date: cal.startOfDay(for: d), total: Int.random(in: 0...100_000_000)))
        d = cal.date(byAdding: .day, value: 1, to: d)!
    }
    return VStack {
        HeatmapView(days: days, fitMode: .fit)
        HeatmapView(days: days, fitMode: .scroll)
    }
    .padding()
    .frame(width: 420)
    .preferredColorScheme(.dark)
}
