import SwiftUI

/// ② 时间范围按钮 + 汇总(总token大字 / 输入/输出/缓存 三列 / 缓存率进度条)。
struct SummaryView: View {
    @Binding var selectedRange: TimeRange
    let summary: SummaryStats
    let onCustomTap: () -> Void

    var body: some View {
        VStack(spacing: UB.Spacing.xl) {
            TimeRangeSelector(selected: $selectedRange, onCustomTap: onCustomTap)

            VStack(spacing: UB.Spacing.xl) {
                Text(formatTokens(summary.total))
                    .font(UB.Font.summaryBig)
                    .foregroundColor(UB.Palette.accent)

                HStack {
                    statCol(formatTokens(summary.input), "输入Token")
                    Spacer()
                    statCol(formatTokens(summary.output), "输出Token")
                    Spacer()
                    statCol(formatTokens(summary.cacheRead + summary.cacheCreate), "缓存Token")
                }

                UsageProgressBar(
                    fraction: summary.cacheRate,
                    text: "缓存率: \(formatCacheRate(summary.cacheRate))",
                    tint: UB.Palette.cache
                )
            }
            .padding(UB.Spacing.xxl)
            .background(UB.Palette.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous)
                    .stroke(UB.Palette.accent.opacity(0.18), lineWidth: 0.5)
            )
        }
    }

    private func statCol(_ value: String, _ label: String) -> some View {
        VStack(spacing: UB.Spacing.xs) {
            Text(value).font(UB.Font.metricBig)
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
        .padding().frame(width: 420)
    }
}
