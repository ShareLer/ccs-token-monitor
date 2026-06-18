import SwiftUI

/// 截图专用：把全部内容（标题 + 模型卡 + 汇总卡 + 趋势图 + 热力图）纵向完整铺开，
/// 不放进 ScrollView、不限制高度，供 ImageRenderer 渲染出含「滚动外」的完整长图。
/// 显式给定宽度，确保热力图内部 GeometryReader 在脱屏渲染时能拿到确定宽度。
struct SnapshotView: View {
    let modelUsages: [ModelUsage]
    let pricing: PricingStore
    let balance: BalanceStore
    let dbPath: String
    let summary: SummaryStats
    let selectedRange: TimeRange
    let expandedModelIDs: Set<String>
    let trend: [TrendPoint]
    let heatmap: [HeatmapDay]
    let heatmapFitMode: HeatmapFitMode
    let appearanceMode: AppAppearanceMode
    let systemAppearanceIsDark: Bool

    var width: CGFloat = 420

    var body: some View {
        VStack(spacing: UB.Spacing.xl) {
            HStack {
                Text("CCS Token Monitor").font(UB.Font.popoverTitle)
                Spacer()
            }
            SummaryView(selectedRange: .constant(selectedRange), summary: summary, onCustomTap: {})
            ModelListView(usages: modelUsages,
                          total: summary.total,
                          expandedModelIDs: .constant(expandedModelIDs),
                          pricing: pricing,
                          balance: balance,
                          dbPath: dbPath)
            TrendChartView(points: trend)
            HeatmapView(days: heatmap, fitMode: heatmapFitMode)
        }
        .padding(UB.Spacing.xxl)
        .frame(width: width)
        .background(UB.Canvas.canvasBackground)
        .preferredColorScheme(appearanceMode.preferredColorScheme(systemIsDark: systemAppearanceIsDark))
    }
}

#Preview {
    let pricing = PricingStore()
    let balance = BalanceStore()
    return SnapshotView(
        modelUsages: [
            ModelUsage(model: "claude-sonnet-4-6", input: 334848, output: 4195578,
                       cacheRead: 333630681, cacheCreate: 33315399),
            ModelUsage(model: "deepseek-v4-pro", input: 5816761, output: 1644166,
                       cacheRead: 270605312, cacheCreate: 0),
        ],
        pricing: pricing,
        balance: balance,
        dbPath: SettingsStore.defaultDBPath,
        summary: SummaryStats(input: 1224276, output: 987654, cacheRead: 200000, cacheCreate: 36622),
        selectedRange: .today,
        expandedModelIDs: ["claude-sonnet-4-6"],
        trend: (1...20).flatMap { i -> [TrendPoint] in
            let d = String(format: "2026-06-%02d", i)
            return [TrendPoint(day: d, model: "claude-sonnet-4-6", total: 800_000 + i * 120_000)]
        },
        heatmap: [],
        heatmapFitMode: .fit,
        appearanceMode: .system,
        systemAppearanceIsDark: false
    )
}
