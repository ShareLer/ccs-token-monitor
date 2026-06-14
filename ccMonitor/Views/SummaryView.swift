import SwiftUI

/// ② 汇总卡：顶部时间范围按钮 + 总计/输入/输出/缓存 四列并排 + 缓存率进度条。
struct SummaryView: View {
    @Binding var selectedRange: TimeRange
    let summary: SummaryStats
    let onCustomTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.xl) {
            TimeRangeSelector(selected: $selectedRange, onCustomTap: onCustomTap)

            Divider()

            // 四列并排，同字体
            HStack(alignment: .top) {
                statCol(formatTokens(summary.total), "总计", accent: true)
                Spacer()
                statCol(formatTokens(summary.input), "输入")
                Spacer()
                statCol(formatTokens(summary.output), "输出")
                Spacer()
                statCol(formatTokens(summary.cacheRead + summary.cacheCreate), "缓存")
            }

            UsageProgressBar(
                fraction: summary.cacheRate,
                text: "缓存率: \(formatCacheRate(summary.cacheRate))",
                tint: UB.Palette.cache
            )
        }
        .ubCard()
    }

    private func statCol(_ value: String, _ label: String, accent: Bool = false) -> some View {
        VStack(spacing: UB.Spacing.xs) {
            Text(value)
                .font(UB.Font.metricBig)
                .foregroundColor(accent ? UB.Palette.accent : .primary)
            Text(label).font(UB.Font.caption).foregroundColor(.secondary)
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
        .padding().frame(width: 420).background(UB.Canvas.canvasBackground)
    }
}
