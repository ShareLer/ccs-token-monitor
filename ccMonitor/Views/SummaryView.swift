import SwiftUI

/// ② 时间范围按钮 + 汇总(总token大字 / 输入/输出/缓存 三列 / 缓存率进度条)。
struct SummaryView: View {
    @Binding var selectedRange: TimeRange
    let summary: SummaryStats
    let onCustomTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            TimeRangeSelector(selected: $selectedRange, onCustomTap: onCustomTap)

            VStack(spacing: 12) {
                Text(formatTokens(summary.total))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: 0x2196F3))

                HStack {
                    statCol(formatTokens(summary.input), "输入Token")
                    Spacer()
                    statCol(formatTokens(summary.output), "输出Token")
                    Spacer()
                    statCol(formatTokens(summary.cacheRead + summary.cacheCreate), "缓存Token")
                }

                UsageProgressBar(
                    fraction: summary.cacheRate,
                    text: "缓存率: \(formatPercent(summary.cacheRate))",
                    height: 12,
                    gradient: LinearGradient(colors: [Color(hex: 0xFFC107), Color(hex: 0xFFA000)],
                                             startPoint: .leading, endPoint: .trailing)
                )
            }
            .padding(16)
            .background(Color(hex: 0xF0F8FF))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0E6FF)))
        }
    }

    private func statCol(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .semibold))
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}

#Preview {
    StatefulPreviewWrapper(TimeRange.today) { binding in
        SummaryView(
            selectedRange: binding,
            summary: SummaryStats(input: 1224276, output: 987654, cacheRead: 200000, cacheCreate: 36622),
            onCustomTap: {}
        )
        .padding().frame(width: 420)
    }
}
