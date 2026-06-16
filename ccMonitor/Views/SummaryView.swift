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

            // 输入是否包含缓存读依数据源不同；总计口径由仓库层统一归一化。
            HStack(alignment: .top) {
                statCol(formatTokens(summary.total), "总计", accent: true)
                Spacer()
                statCol(formatTokens(summary.cacheRead), "缓存")
                Spacer()
                statCol(formatTokens(summary.input + summary.cacheCreate), "输入")
                Spacer()
                statCol(formatTokens(summary.output), "输出")
            }

            UsageProgressBar(
                fraction: summary.cacheRate,
                text: "缓存率: \(formatCacheRate(summary.cacheRate))",
                tint: UB.Palette.cacheRateColor(summary.cacheRate)
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
