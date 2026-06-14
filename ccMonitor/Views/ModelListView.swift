import SwiftUI

/// ① 模型列表：整体一张卡，卡内每个模型一行（行间细分隔线），UsageBoard 风格。
struct ModelListView: View {
    let usages: [ModelUsage]
    let pricing: PricingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(usages.enumerated()), id: \.element.id) { index, u in
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
