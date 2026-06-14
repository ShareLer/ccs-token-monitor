import SwiftUI

/// 顶部时间范围按钮组：当日 / 7d / 30d / 自定义。
struct TimeRangeSelector: View {
    @Binding var selected: TimeRange
    let onCustomTap: () -> Void

    private func isActive(_ r: TimeRange) -> Bool {
        switch (selected, r) {
        case (.today, .today), (.last7d, .last7d), (.last30d, .last30d): return true
        case (.custom, .custom): return true
        default: return false
        }
    }

    private func chip(_ title: String, _ range: TimeRange, custom: Bool = false) -> some View {
        Button(action: {
            if custom { onCustomTap() } else { selected = range }
        }) {
            Text(title)
                .font(.system(size: 12))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isActive(range) ? Color(hex: 0x2196F3) : Color(hex: 0xF0F0F0))
                .foregroundColor(isActive(range) ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 6) {
            chip("当日", .today)
            chip("7天", .last7d)
            chip("30天", .last30d)
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
