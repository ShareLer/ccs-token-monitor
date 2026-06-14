import SwiftUI

/// ① 模型列表：每行 模型名 + 缓存率 + 成本 + 进度条(今日/本月)。
struct ModelListView: View {
    let usages: [ModelUsage]
    let pricing: PricingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(usages) { u in
                VStack(spacing: 8) {
                    HStack {
                        Text(u.model)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("缓存率: \(formatCacheRate(u.cacheRate))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: 0xFFC107))
                        Text("成本: \(formatCost(u.cost(with: pricing.pricing(for: u.model))))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: 0x4CAF50))
                    }
                    UsageProgressBar(
                        fraction: u.monthTotal == 0 ? 0 : Double(u.todayTotal) / Double(u.monthTotal),
                        text: "\(formatTokens(u.todayTotal)) / \(formatTokens(u.monthTotal))"
                    )
                }
                .padding(12)
                .background(Color(hex: 0xFAFAFA))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xEEEEEE)))
            }
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
    .padding().frame(width: 420)
}
