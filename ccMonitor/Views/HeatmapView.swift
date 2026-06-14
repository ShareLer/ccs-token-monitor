import SwiftUI

/// ④ Token 活动热力图（本自然年，7 行 × N 列）。
/// fit 模式：动态缩放格子完全显示不滑动；scroll 模式：固定格子可横向滑动。
struct HeatmapView: View {
    let days: [HeatmapDay]
    var fitMode: HeatmapFitMode = .fit

    private let gap: CGFloat = 3
    private let scrollCell: CGFloat = 11   // scroll 模式固定格子边长

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
        switch lvl {
        case 1: return Color(hex: 0xD6E685)
        case 2: return Color(hex: 0x8CC665)
        case 3: return Color(hex: 0x44A340)
        case 4: return Color(hex: 0x1E6823)
        default: return Color(hex: 0xE0E0E0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token活动").font(UB.Font.sectionTitle)
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
                                .help("\(key): \(formatTokens(totalByDay[key] ?? 0))")
                        }
                    }
                }
            }
            monthLabels(cell: cell)
        }
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
    }.padding().frame(width: 420)
}
