import SwiftUI

enum ProgressBarGeometry {
    static func fillWidth(fraction: Double, totalWidth: CGFloat) -> CGFloat {
        max(0, min(1, fraction)) * max(0, totalWidth)
    }
}

/// 胶囊进度条（UsageBoard 风格）：主色淡底 + 主色填充 + 居中加粗文字。
struct UsageProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appBackgroundStyle) private var appBackgroundStyle

    let fraction: Double      // 0...1
    let text: String          // 叠加显示的文字，如 "12.5K / 1.2M"
    var height: CGFloat = 18
    var tint: Color = UB.Palette.accent

    var body: some View {
        GeometryReader { geo in
            let width = ProgressBarGeometry.fillWidth(fraction: fraction, totalWidth: geo.size.width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous)
                    .fill(trackFill)
                Rectangle()
                    .fill(fillStyle)
                    .frame(width: width)
                    .overlay(alignment: .top) {
                        if appBackgroundStyle == .glass && width > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.28))
                                .frame(height: 1)
                        }
                    }
                Text(text)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(labelColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous)
                .stroke(trackStroke, lineWidth: appBackgroundStyle == .glass ? 0.7 : 0)
        )
    }

    private var trackFill: Color {
        if appBackgroundStyle == .glass {
            return UB.Glass.controlFill(for: colorScheme)
        }
        return tint.opacity(0.16)
    }

    private var trackStroke: Color {
        UB.Glass.subtleBorder(for: colorScheme)
    }

    private var fillStyle: AnyShapeStyle {
        if appBackgroundStyle == .glass {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        tint.opacity(colorScheme == .dark ? 0.88 : 0.94),
                        tint.opacity(colorScheme == .dark ? 0.68 : 0.76),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(tint)
    }

    private var labelColor: Color {
        if appBackgroundStyle == .glass {
            return colorScheme == .dark ? .white.opacity(0.92) : .primary.opacity(0.86)
        }
        return colorScheme == .dark ? .white : .black
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

#Preview {
    VStack(spacing: 12) {
        UsageProgressBar(fraction: 0.32, text: "12.5K / 39K")
        UsageProgressBar(fraction: 0.75, text: "750K / 1.0M")
        UsageProgressBar(fraction: 0.05, text: "5K / 100K")
        UsageProgressBar(fraction: 0.6, text: "缓存率: 60%", tint: UB.Palette.cache)
    }
    .padding()
    .frame(width: 380)
}
