import SwiftUI

/// 截图专用：把全部内容（标题 + 模型卡 + 汇总卡 + 趋势图 + 热力图）纵向完整铺开，
/// 不放进 ScrollView、不限制高度，供 ImageRenderer 渲染出含「滚动外」的完整长图。
/// 显式给定宽度，确保热力图内部 GeometryReader 在脱屏渲染时能拿到确定宽度。
struct SnapshotView: View {
    let modelUsages: [ModelUsage]
    let pricing: PricingStore
    let summary: SummaryStats
    let selectedRange: TimeRange
    let trend: [TrendPoint]
    let heatmap: [HeatmapDay]
    let heatmapFitMode: HeatmapFitMode

    var width: CGFloat = 420

    var body: some View {
        VStack(spacing: UB.Spacing.xl) {
            HStack {
                Text("CCS Token Monitor").font(UB.Font.popoverTitle)
                Spacer()
            }
            ModelListView(usages: modelUsages, pricing: pricing)
            SummaryView(selectedRange: .constant(selectedRange), summary: summary, onCustomTap: {})
            TrendChartView(points: trend)
            HeatmapView(days: heatmap, fitMode: heatmapFitMode)
        }
        .padding(UB.Spacing.xxl)
        .frame(width: width)
        .background(UB.Canvas.canvasBackground)
    }
}

#Preview {
    let pricing = PricingStore()
    return SnapshotView(
        modelUsages: [
            ModelUsage(model: "claude-sonnet-4-6", monthInput: 334848, monthOutput: 4195578,
                       monthCacheRead: 333630681, monthCacheCreate: 33315399, todayTotal: 120000),
            ModelUsage(model: "deepseek-v4-pro", monthInput: 5816761, monthOutput: 1644166,
                       monthCacheRead: 270605312, monthCacheCreate: 0, todayTotal: 30000),
        ],
        pricing: pricing,
        summary: SummaryStats(input: 1224276, output: 987654, cacheRead: 200000, cacheCreate: 36622),
        selectedRange: .today,
        trend: (1...20).flatMap { i -> [TrendPoint] in
            let d = String(format: "2026-06-%02d", i)
            return [TrendPoint(day: d, model: "claude-sonnet-4-6", total: 800_000 + i * 120_000)]
        },
        heatmap: [],
        heatmapFitMode: .fit
    )
}
