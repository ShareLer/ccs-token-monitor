import SwiftUI

/// ④ 7×52 热力图，按日总token分5档(无活动=灰)。
struct HeatmapView: View {
    let days: [HeatmapDay]

    private let weeks = 52
    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    private var totalByDay: [String: Int] {
        let f = Self.dayFormatter
        return Dictionary(days.map { (f.string(from: $0.date), $0.total) }, uniquingKeysWith: +)
    }
    private var maxTotal: Int { days.map { $0.total }.max() ?? 0 }

    private var grid: [[Date]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let lastSunday = cal.date(byAdding: .day, value: -(weekday - 1), to: today)!
        var cols: [[Date]] = []
        for w in stride(from: weeks - 1, through: 0, by: -1) {
            let colStart = cal.date(byAdding: .day, value: -w * 7, to: lastSunday)!
            var col: [Date] = []
            for d in 0..<7 {
                col.append(cal.date(byAdding: .day, value: d, to: colStart)!)
            }
            cols.append(col)
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
            Text("Token活动").font(.system(size: 14, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gap) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(Array(grid.enumerated()), id: \.offset) { _, col in
                            VStack(spacing: gap) {
                                ForEach(Array(col.enumerated()), id: \.offset) { _, day in
                                    let key = Self.dayFormatter.string(from: day)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color(level(totalByDay[key] ?? 0)))
                                        .frame(width: cell, height: cell)
                                        .help("\(key): \(formatTokens(totalByDay[key] ?? 0))")
                                }
                            }
                        }
                    }
                    monthLabels
                }
            }
        }
        .padding(16)
        .background(Color(hex: 0xFAFAFA))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xEEEEEE)))
    }

    private var monthLabels: some View {
        HStack(spacing: gap) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, col in
                let first = col.first!
                let cal = Calendar.current
                let dayNum = cal.component(.day, from: first)
                Text(dayNum <= 7 ? Self.monthFormatter.string(from: first) : "")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .frame(width: cell)
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
    for i in 0..<120 {
        let d = cal.date(byAdding: .day, value: -i, to: Date())!
        days.append(HeatmapDay(date: cal.startOfDay(for: d), total: Int.random(in: 0...100_000_000)))
    }
    return HeatmapView(days: days).padding().frame(width: 420)
}
