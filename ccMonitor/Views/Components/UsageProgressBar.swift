import SwiftUI

/// 圆角进度条：蓝色渐变填充 + 黑色加粗叠加文字（对比度硬性要求）。
struct UsageProgressBar: View {
    let fraction: Double      // 0...1
    let text: String          // 叠加显示的文字，如 "12.5K / 1.2M"
    var height: CGFloat = 14
    var gradient = LinearGradient(colors: [Color(hex: 0x2196F3), Color(hex: 0x21CBF3)],
                                  startPoint: .leading, endPoint: .trailing)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color(hex: 0xE0E0E0))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(gradient)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)   // 黑色，任意背景对比度
            }
        }
        .frame(height: height)
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
    }
    .padding()
    .frame(width: 380)
}
