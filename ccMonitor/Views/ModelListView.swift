import SwiftUI

/// ① 模型列表：整体一张卡，卡内每个模型一行（行间细分隔线），UsageBoard 风格。
struct ModelListView: View {
    let usages: [ModelUsage]
    // 必须 @ObservedObject：价格在设置面板改动后，PricingStore 变化要直接驱动本视图重绘。
    // 若用普通 let，由于 usages（不含价格字段）刷新前后 Equatable 相等、pricing 又是同一引用，
    // SwiftUI 会 diff 跳过重绘，导致成本一直停留在旧值（如 $0.00）。
    @ObservedObject var pricing: PricingStore

    var body: some View {
        let shown = ModelUsage.topFive(from: usages)
        return VStack(alignment: .leading, spacing: 0) {
            Text("模型用量明细")
                .font(UB.Font.sectionTitle)
                .padding(.bottom, UB.Spacing.xl)
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, u in
                if index > 0 {
                    Divider().padding(.vertical, UB.Spacing.l)
                }
                row(u)
            }
        }
        .ubCard()
    }

    private func row(_ u: ModelUsage) -> some View {
        VStack(spacing: UB.Spacing.m) {
            HStack {
                Text(u.model)
                    .font(UB.Font.cardTitle)
                    .lineLimit(1)
                Spacer()
                Text("缓存 \(formatCacheRate(u.cacheRate))")
                    .font(UB.Font.label)
                    .foregroundColor(UB.Palette.cache)
                Text(formatCost(u.cost(with: pricing.pricing(for: u.model))))
                    .font(UB.Font.label)
                    .foregroundColor(UB.Palette.cost)
            }
            UsageProgressBar(
                fraction: u.monthTotal == 0 ? 0 : Double(u.todayTotal) / Double(u.monthTotal),
                text: "\(formatTokens(u.todayTotal)) / \(formatTokens(u.monthTotal))"
            )
        }
    }
}

#Preview {
    let pricing = PricingStore()
    return ModelListView(usages: [
        ModelUsage(model: "claude-sonnet-4-6", monthInput: 334848, monthOutput: 4195578,
                   monthCacheRead: 333630681, monthCacheCreate: 33315399, todayTotal: 120000),
        ModelUsage(model: "deepseek-v4-pro", monthInput: 5816761, monthOutput: 1644166,
                   monthCacheRead: 270605312, monthCacheCreate: 0, todayTotal: 30000),
    ], pricing: pricing)
    .padding().frame(width: 420).background(UB.Canvas.canvasBackground)
}
