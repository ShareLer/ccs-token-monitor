import SwiftUI

/// ① 模型列表：整体一张卡，卡内每个模型一行（行间细分隔线），UsageBoard 风格。
struct ModelListView: View {
    let usages: [ModelUsage]
    let total: Int
    @Binding var expandedModelIDs: Set<String>
    // 必须 @ObservedObject：价格在设置面板改动后，PricingStore 变化要直接驱动本视图重绘。
    // 若用普通 let，由于 usages（不含价格字段）刷新前后 Equatable 相等、pricing 又是同一引用，
    // SwiftUI 会 diff 跳过重绘，导致成本一直停留在旧值（如 $0.00）。
    @ObservedObject var pricing: PricingStore
    @ObservedObject var balance: BalanceStore
    let dbPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("模型用量明细")
                .font(UB.Font.sectionTitle)
                .padding(.bottom, UB.Spacing.xl)
            ForEach(Array(usages.enumerated()), id: \.element.id) { index, u in
                if index > 0 {
                    UBDivider(style: .hairline).padding(.vertical, UB.Spacing.l)
                }
                row(u, isExpanded: expandedModelIDs.contains(u.id))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleExpanded(u.id)
                    }
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    private func row(_ u: ModelUsage, isExpanded: Bool) -> some View {
        let share = total == 0 ? 0 : Double(u.total) / Double(total)
        return VStack(alignment: .leading, spacing: UB.Spacing.m) {
            rowHeader(u, isExpanded: isExpanded)
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

    @ViewBuilder
    private func rowHeader(_ u: ModelUsage, isExpanded: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            horizontalHeader(u, isExpanded: isExpanded, valuesVisible: true)
            horizontalHeader(u, isExpanded: isExpanded, valuesVisible: false)

            VStack(alignment: .leading, spacing: UB.Spacing.s) {
                HStack(spacing: UB.Spacing.s) {
                    Text(u.model)
                        .font(UB.Font.cardTitle)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(u.model)
                    Spacer(minLength: UB.Spacing.m)
                    disclosureIcon(isExpanded: isExpanded)
                }
                ViewThatFits(in: .horizontal) {
                    metrics(for: u, valuesVisible: true)
                    metrics(for: u, valuesVisible: false)
                }
            }
        }
    }

    private func horizontalHeader(_ u: ModelUsage, isExpanded: Bool, valuesVisible: Bool) -> some View {
        HStack(spacing: UB.Spacing.s) {
            Text(u.model)
                .font(UB.Font.cardTitle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help(u.model)
            Spacer(minLength: UB.Spacing.m)
            metrics(for: u, valuesVisible: valuesVisible)
            disclosureIcon(isExpanded: isExpanded)
        }
    }

    private func metrics(for u: ModelUsage, valuesVisible: Bool) -> some View {
        HStack(spacing: UB.Spacing.m) {
            balanceMetric(for: u.model, valuesVisible: valuesVisible)
            metricLabel(
                systemName: "memorychip",
                value: formatCacheRate(u.cacheRate),
                color: UB.Palette.cacheRateColor(u.cacheRate),
                help: "缓存率 \(formatCacheRate(u.cacheRate))",
                valuesVisible: valuesVisible
            )
            metricLabel(
                systemName: "dollarsign.circle",
                value: formatCost(u.cost(with: pricing.pricing(for: u.model))),
                color: UB.Palette.cost,
                help: "消费 \(formatCost(u.cost(with: pricing.pricing(for: u.model))))",
                valuesVisible: valuesVisible
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func balanceMetric(for model: String, valuesVisible: Bool) -> some View {
        if balance.effectiveRule(for: model) != nil {
            metricLabel(
                systemName: "creditcard",
                value: balanceText(for: model),
                color: balanceColor(for: model),
                help: balanceHelp(for: model),
                valuesVisible: valuesVisible
            )
        }
    }

    private func metricLabel(systemName: String, value: String, color: Color, help: String, valuesVisible: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 11)
            if valuesVisible {
                Text(value)
                    .font(.system(size: 10.8, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
        }
        .frame(minWidth: valuesVisible ? nil : 13, minHeight: 13)
        .foregroundColor(color)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(help))
    }

    private func disclosureIcon(isExpanded: Bool) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
            UBDivider(style: .hairline)
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

    private func balanceText(for model: String) -> String {
        guard let modelBalance = balance.balance(for: model) else {
            return "未刷新"
        }
        switch modelBalance.state {
        case .idle:
            return "未刷新"
        case .loading:
            return "查询中"
        case .value(let value, let currency):
            return formatBalance(value, currency: currency)
        case .failed:
            return "失败"
        }
    }

    private func balanceHelp(for model: String) -> String {
        guard let modelBalance = balance.balance(for: model) else {
            return "尚未查询余额"
        }
        switch modelBalance.state {
        case .failed(let message):
            return message
        case .value(let value, let currency):
            return "余额 \(formatBalance(value, currency: currency))"
        case .loading:
            return "正在查询余额"
        case .idle:
            return "尚未查询余额"
        }
    }

    private func balanceColor(for model: String) -> Color {
        guard let modelBalance = balance.balance(for: model) else {
            return .secondary
        }
        switch modelBalance.state {
        case .value:
            return UB.Palette.balance
        case .failed:
            return .red
        case .loading, .idle:
            return .secondary
        }
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
        UBDivider(orientation: .vertical, style: .hairline, length: 28)
    }
}

#Preview {
    let pricing = PricingStore()
    let balance = BalanceStore()
    return VStack(spacing: UB.Spacing.xl) {
        ModelListView(usages: [
            ModelUsage(model: "claude-sonnet-4-6", input: 334848, output: 4195578,
                       cacheRead: 333630681, cacheCreate: 33315399),
            ModelUsage(model: "deepseek-v4-pro", input: 5816761, output: 1644166,
                       cacheRead: 270605312, cacheCreate: 0),
        ], total: 700_000_000, expandedModelIDs: .constant([]), pricing: pricing, balance: balance, dbPath: SettingsStore.defaultDBPath)
        ModelListView(usages: [], total: 0, expandedModelIDs: .constant([]), pricing: pricing, balance: balance, dbPath: SettingsStore.defaultDBPath)
    }
    .padding().frame(width: 420).background(UB.Canvas.canvasBackground)
}
