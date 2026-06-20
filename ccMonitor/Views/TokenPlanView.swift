import SwiftUI

private enum TokenPlanLayout {
    static let tierLabelWidth: CGFloat = 46
    static let resetWidth: CGFloat = 54
    static let progressHeight: CGFloat = 16
    static let tiers: [TokenPlanTierKind] = [.fiveHour, .weekly]
}

struct TokenPlanView: View {
    @ObservedObject var store: TokenPlanStore

    var body: some View {
        if store.shouldDisplay {
            VStack(alignment: .leading, spacing: UB.Spacing.l) {
                Text("Token Plan")
                    .font(UB.Font.sectionTitle)

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: UB.Spacing.l) {
                        ForEach(store.activeConfigs) { config in
                            TokenPlanProviderRow(config: config,
                                                 quota: store.quota(for: config.id),
                                                 state: store.state(for: config.id),
                                                 now: context.date)
                            if config.id != store.activeConfigs.last?.id {
                                UBDivider(style: .hairline)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard()
        }
    }
}

private struct TokenPlanProviderRow: View {
    let config: TokenPlanConfig
    let quota: TokenPlanQuota?
    let state: TokenPlanLoadState
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: UB.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: UB.Spacing.s) {
                    Text(config.id.displayName)
                        .font(UB.Font.itemTitle)
                        .lineLimit(1)
                    if let planLabel {
                        Text(planLabel)
                            .font(UB.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: UB.Spacing.m)
                Text(statusText)
                    .font(UB.Font.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            VStack(spacing: UB.Spacing.s) {
                ForEach(TokenPlanLayout.tiers) { kind in
                    TokenPlanProgressRow(kind: kind,
                                         tier: quota?.tier(for: kind),
                                         state: state,
                                         now: now)
                }
            }
            .padding(.leading, UB.Spacing.m)
        }
    }

    private var planLabel: String? {
        let label = quota?.planLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let label, !label.isEmpty else { return nil }
        return label
    }

    private var statusText: String {
        switch state {
        case .idle:
            return "尚未查询"
        case .loading:
            return "查询中"
        case .loaded:
            if let queriedAt = quota?.queriedAt {
                return "更新于 \(formatShortTime(queriedAt))"
            }
            return "已更新"
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        if case .failed = state {
            return .red
        }
        return .secondary
    }

    private func formatShortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct TokenPlanProgressRow: View {
    let kind: TokenPlanTierKind
    let tier: TokenPlanTier?
    let state: TokenPlanLoadState
    let now: Date

    var body: some View {
        HStack(spacing: UB.Spacing.m) {
            Text(kind.displayName)
                .font(UB.Font.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: TokenPlanLayout.tierLabelWidth, alignment: .leading)
            TokenPlanProgressBar(fraction: tier?.clampedFraction ?? 0,
                                 text: centerText,
                                 color: progressColor,
                                 isPlaceholder: tier == nil)
            Text(resetText)
                .font(UB.Font.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: TokenPlanLayout.resetWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var centerText: String {
        guard let tier else {
            return state == .loading ? "..." : "--"
        }
        return "\(Int(tier.utilization.rounded()))%"
    }

    private var resetText: String {
        guard let tier else {
            switch state {
            case .loading: return "查询中"
            case .failed: return "失败"
            default: return "未返回"
            }
        }
        guard let resetsAt = tier.resetsAt else {
            return "无时间"
        }
        let seconds = Int(resetsAt.timeIntervalSince(now).rounded(.down))
        guard seconds > 0 else {
            return "待刷新"
        }
        return formatDuration(seconds)
    }

    private var progressColor: Color {
        guard let tier else {
            return .secondary.opacity(0.35)
        }
        if tier.utilization >= 90 {
            return .red
        }
        if tier.utilization >= 70 {
            return .orange
        }
        return UB.Palette.balance
    }

    private var accessibilityText: String {
        "\(kind.displayName) \(centerText)，\(resetText)"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "\(days)d\(hours % 24)h"
        }
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct TokenPlanProgressBar: View {
    let fraction: Double
    let text: String
    let color: Color
    let isPlaceholder: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appBackgroundStyle) private var appBackgroundStyle

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, min(proxy.size.width * fraction, proxy.size.width))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackFill)
                    .overlay(
                        Capsule()
                            .stroke(trackStroke, lineWidth: appBackgroundStyle == .glass ? 0.7 : 0)
                    )
                Capsule()
                    .fill(fillStyle)
                    .frame(width: width)
                    .overlay(alignment: .top) {
                        if appBackgroundStyle == .glass && width > 0 {
                            Capsule()
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.26))
                                .frame(height: 1)
                        }
                    }
                Text(text)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isPlaceholder ? .secondary : labelColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(height: TokenPlanLayout.progressHeight)
    }

    private var trackFill: Color {
        if appBackgroundStyle == .glass {
            return UB.Glass.controlFill(for: colorScheme)
        }
        return Color.primary.opacity(0.08)
    }

    private var trackStroke: Color {
        UB.Glass.subtleBorder(for: colorScheme)
    }

    private var fillStyle: AnyShapeStyle {
        let opacity = isPlaceholder ? 0.24 : (colorScheme == .dark ? 0.68 : 0.76)
        if appBackgroundStyle == .glass {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [color.opacity(opacity), color.opacity(max(opacity - 0.18, 0.18))],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(color.opacity(isPlaceholder ? 0.25 : 0.86))
    }

    private var labelColor: Color {
        appBackgroundStyle == .glass
            ? (colorScheme == .dark ? .white.opacity(0.9) : .primary.opacity(0.86))
            : .primary
    }
}

#Preview {
    let store = TokenPlanStore()
    store.setConfig(TokenPlanConfig(id: .kimi,
                                    enabled: true,
                                    baseUrl: "https://api.kimi.com/coding",
                                    apiKey: "sk-test"))
    store.setConfig(TokenPlanConfig(id: .zhipu,
                                    enabled: true,
                                    baseUrl: "https://open.bigmodel.cn",
                                    apiKey: "sk-test"))
    return TokenPlanView(store: store)
        .padding()
        .frame(width: 420)
        .background(UB.Canvas.canvasBackground)
}
