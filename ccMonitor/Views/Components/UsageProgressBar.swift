import SwiftUI

/// 胶囊进度条（UsageBoard 风格）：主色淡底 + 主色填充 + 居中黑色加粗文字。
/// 文字固定黑色（CLAUDE.md 硬性要求：任意背景下最佳对比度）。
struct UsageProgressBar: View {
    let fraction: Double      // 0...1
    let text: String          // 叠加显示的文字，如 "12.5K / 1.2M"
    var height: CGFloat = 18
    var tint: Color = UB.Palette.accent

    var body: some View {
        GeometryReader { geo in
            let ratio = max(0, min(1, fraction))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous)
                    .fill(tint.opacity(0.16))
                RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous)
                    .fill(tint)
                    .frame(width: ratio * geo.size.width)
                Text(text)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.black)   // 黑色，任意背景对比度（CLAUDE.md 要求）
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.bar, style: .continuous))
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
