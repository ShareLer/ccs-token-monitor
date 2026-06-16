import SwiftUI

/// ① 模型列表：整体一张卡，卡内每个模型一行（行间细分隔线），UsageBoard 风格。
struct ModelListView: View {
    let usages: [ModelUsage]
    let total: Int
    @State private var expandedModelIDs: Set<String> = []
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
                row(u, isExpanded: expandedModelIDs.contains(u.id))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleExpanded(u.id)
                    }
                    .accessibilityAddTraits(.isButton)
            }
        }
        .ubCard()
    }

    private func row(_ u: ModelUsage, isExpanded: Bool) -> some View {
        let share = total == 0 ? 0 : Double(u.total) / Double(total)
        return VStack(alignment: .leading, spacing: UB.Spacing.m) {
            HStack(spacing: UB.Spacing.s) {
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            UsageProgressBar(
                fraction: share,
                text: "\(formatTokens(u.total)) · \(formatPercent(share))"
            )
            if isExpanded {
                expandedStats(for: u)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleExpanded(_ id: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedModelIDs.contains(id) {
                expandedModelIDs.remove(id)
            } else {
                expandedModelIDs.insert(id)
            }
        }
    }

    private func expandedStats(for u: ModelUsage) -> some View {
        VStack(spacing: UB.Spacing.m) {
            Divider()
            HStack(spacing: 0) {
                detailStat(formatTokens(u.total), "总计", color: UB.Palette.accent)
                verticalDivider()
                detailStat(formatTokens(u.cacheRead), "缓存", color: UB.Palette.cache)
                verticalDivider()
                detailStat(formatTokens(u.input + u.cacheCreate), "输入")
                verticalDivider()
                detailStat(formatTokens(u.output), "输出")
            }
        }
        .padding(.top, UB.Spacing.xs)
    }

    private func detailStat(_ value: String, _ label: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: UB.Spacing.xs) {
            Text(value)
                .font(UB.Font.metricBig)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(UB.Font.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UB.Spacing.s)
    }

    private func verticalDivider() -> some View {
        Rectangle()
            .fill(UB.Canvas.separator.opacity(0.65))
            .frame(width: 0.5, height: 28)
    }
}

#Preview {
    let pricing = PricingStore()
    return ModelListView(usages: [
        ModelUsage(model: "claude-sonnet-4-6", input: 334848, output: 4195578,
                   cacheRead: 333630681, cacheCreate: 33315399),
        ModelUsage(model: "deepseek-v4-pro", input: 5816761, output: 1644166,
                   cacheRead: 270605312, cacheCreate: 0),
    ], total: 700_000_000, pricing: pricing)
    .padding().frame(width: 420).background(UB.Canvas.canvasBackground)
}
