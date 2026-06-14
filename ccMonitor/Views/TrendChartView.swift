import SwiftUI
import Charts

/// ③ 最近30天用量趋势，多模型多色线，悬停显示当天全部模型。
struct TrendChartView: View {
    let points: [TrendPoint]

    @State private var selectedDay: String?

    private var models: [String] {
        Array(Set(points.map { $0.model })).sorted()
    }
    private var daySelection: [TrendPoint] {
        guard let d = selectedDay else { return [] }
        return points.filter { $0.day == d }.sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近30天用量趋势").font(.system(size: 14, weight: .semibold))

            Chart {
                ForEach(points) { p in
                    LineMark(
                        x: .value("日期", p.day),
                        y: .value("Token", p.total)
                    )
                    .foregroundStyle(by: .value("模型", p.model))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale(domain: models, range: palette(models.count))
            .chartLegend(.hidden)
            .frame(height: 160)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let frame = geo[proxy.plotAreaFrame]
                                let day: String? = proxy.value(atX: location.x - frame.origin.x)
                                selectedDay = day
                            case .ended:
                                selectedDay = nil
                            }
                        }
                }
            }

            if !daySelection.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay ?? "").font(.system(size: 11, weight: .bold))
                    ForEach(daySelection) { p in
                        Text("\(p.model): \(formatTokens(p.total))")
                            .font(.system(size: 11))
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.8))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(16)
        .background(Color(hex: 0xFAFAFA))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xEEEEEE)))
    }

    private func palette(_ n: Int) -> [Color] {
        let base: [Color] = [0x2196F3, 0x4CAF50, 0xFF9800, 0xE91E63, 0x9C27B0,
                             0x00BCD4, 0x795548, 0x607D8B, 0xCDDC39, 0xFF5722].map { Color(hex: $0) }
        return Array((0..<max(1, n)).map { base[$0 % base.count] })
    }
}

#Preview {
    let days = ["2026-06-10", "2026-06-11", "2026-06-12", "2026-06-13"]
    var pts: [TrendPoint] = []
    for (i, d) in days.enumerated() {
        pts.append(TrendPoint(day: d, model: "claude-sonnet-4-6", total: 1_000_000 * (i + 1)))
        pts.append(TrendPoint(day: d, model: "deepseek-v4-pro", total: 500_000 * (i + 2)))
    }
    return TrendChartView(points: pts).padding().frame(width: 420)
}
