import SwiftUI

/// 顶部时间范围按钮组：当日 / 7d / 30d / 当月 / 当年 / 自定义。
struct TimeRangeSelector: View {
    @Binding var selected: TimeRange
    let onCustomTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appBackgroundStyle) private var appBackgroundStyle

    private func isActive(_ r: TimeRange) -> Bool {
        switch (selected, r) {
        case (.today, .today), (.last7d, .last7d), (.last30d, .last30d), (.thisMonth, .thisMonth), (.thisYear, .thisYear): return true
        case (.custom, .custom): return true
        default: return false
        }
    }

    private func chip(_ title: String, _ range: TimeRange, custom: Bool = false) -> some View {
        let active = isActive(range)
        return Button(action: {
            if custom { onCustomTap() } else { selected = range }
        }) {
            Text(title)
                .font(UB.Font.label)
                .padding(.horizontal, UB.Spacing.xl).padding(.vertical, UB.Spacing.s)
                .background(chipFill(active: active), in: Capsule())
                .overlay(Capsule().stroke(chipBorder(active: active), lineWidth: appBackgroundStyle == .glass ? 0.7 : 0))
                .foregroundColor(active ? .white : inactiveText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func chipFill(active: Bool) -> AnyShapeStyle {
        if active {
            if appBackgroundStyle != .glass {
                return AnyShapeStyle(UB.Palette.accent)
            }
            return AnyShapeStyle(
                LinearGradient(
                    colors: [UB.Palette.accent, UB.Palette.accent.opacity(0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        if appBackgroundStyle == .glass {
            return AnyShapeStyle(UB.Glass.controlFill(for: colorScheme))
        }
        return AnyShapeStyle(UB.Palette.accent.opacity(0.10))
    }

    private func chipBorder(active: Bool) -> Color {
        if active {
            return Color.white.opacity(appBackgroundStyle == .glass ? 0.22 : 0)
        }
        return UB.Glass.subtleBorder(for: colorScheme)
    }

    private var inactiveText: Color {
        appBackgroundStyle == .glass
            ? .primary.opacity(colorScheme == .dark ? 0.78 : 0.72)
            : UB.Palette.accent
    }

    var body: some View {
        HStack(spacing: UB.Spacing.s) {
            chip("当日", .today)
            chip("7天", .last7d)
            chip("30天", .last30d)
            chip("当月", .thisMonth)
            chip("当年", .thisYear)
            chip("自定义", .custom(Date(), Date()), custom: true)
            Spacer()
        }
    }
}

#Preview {
    StatefulPreviewWrapper(TimeRange.today) { binding in
        TimeRangeSelector(selected: binding, onCustomTap: {})
            .padding().frame(width: 380)
    }
}

/// Preview 辅助：让 @Binding 在 Preview 里可变。
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(_ initial: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial); self.content = content
    }
    var body: some View { content($value) }
}
