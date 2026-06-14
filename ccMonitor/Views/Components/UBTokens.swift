import SwiftUI

/// 缓存率分档（纯逻辑，不依赖配色，便于单测边界）。
/// 阈值：<80% low，80~95% medium，>=95% high。边界 80→medium、95→high。
enum CacheRateLevel {
    case low, medium, high

    static func from(fraction: Double) -> CacheRateLevel {
        let pct = fraction * 100
        if pct < 80 { return .low }
        if pct < 95 { return .medium }
        return .high
    }
}

/// 设计 token 体系（参考 UsageBoard），统一间距/圆角/字体/配色。
enum UB {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 10
        static let bar: CGFloat = 5
        static let tile: CGFloat = 6
        static let control: CGFloat = 5
        static let pill: CGFloat = 999
    }

    enum Font {
        static let popoverTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let cardTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let sectionTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 12.5)
        static let label = SwiftUI.Font.system(size: 11.5)
        static let caption = SwiftUI.Font.system(size: 11)
        static let summaryBig = SwiftUI.Font.system(size: 26, weight: .bold).monospacedDigit()
        static let metricBig = SwiftUI.Font.system(size: 14, weight: .semibold).monospacedDigit()
        static let countdown = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()
    }

    enum Canvas {
        /// popover 根背景（浅灰，卡片浮于其上形成层次）
        static let canvasBackground = Color(red: 0.961, green: 0.961, blue: 0.969)
        /// 卡片背景（纯白/深色模式自适应）
        static let cardBackground = Color(nsColor: .textBackgroundColor)
        /// 顶栏背景
        static let barBackground = Color(nsColor: .windowBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)
    }

    enum Palette {
        static let accent = Color(hex: 0x2196F3)        // 主蓝
        static let cache = Color(hex: 0xFFC107)         // 缓存（琥珀）
        static let cost = Color(hex: 0x4CAF50)          // 成本（绿）

        // 缓存率分档色：<80 浅红、80~95 黄、>=95 绿
        static let cacheLow = Color(hex: 0xEF9A9A)      // 浅红
        static let cacheMid = Color(hex: 0xFFC107)      // 黄（琥珀）
        static let cacheHigh = Color(hex: 0x4CAF50)     // 绿

        /// 按缓存率 fraction(0...1) 取分档色。
        static func cacheRateColor(_ fraction: Double) -> Color {
            switch CacheRateLevel.from(fraction: fraction) {
            case .low: return cacheLow
            case .medium: return cacheMid
            case .high: return cacheHigh
            }
        }

        /// 折线/多模型区分色
        static let series: [Color] = [.blue, .green, .orange, .purple, .pink,
                                      .teal, .red, .indigo, .mint, .cyan, .yellow]
        static func seriesColor(_ i: Int) -> Color {
            if i < series.count { return series[i] }
            let hue = Double((i - series.count) % 24) / 24.0
            return Color(hue: hue, saturation: 0.72, brightness: 0.78)
        }

        /// 柔和多色板（低饱和、高明度，Tableau/AntV 风）：用于柱状堆叠等大面积色块，
        /// 与浅灰底/白卡片/柔蓝主调协调，不刺眼。
        static let softSeries: [Color] = [
            Color(hex: 0x5B8FF9),   // 蓝
            Color(hex: 0x61DDAA),   // 青绿
            Color(hex: 0xF6BD16),   // 橙黄
            Color(hex: 0xF08BB4),   // 珊瑚
            Color(hex: 0x9270CA),   // 紫
            Color(hex: 0x78D3F8),   // 天蓝
            Color(hex: 0xFF9D4D),   // 橙
            Color(hex: 0x269A99),   // 墨绿
            Color(hex: 0xBEA0DD),  // 浅紫
            Color(hex: 0x6DC8EC),   // 湖蓝
        ]
        /// 超出预设色板时回落到柔和 HSB（低饱和、高明度）。
        static func softSeriesColor(_ i: Int) -> Color {
            if i < softSeries.count { return softSeries[i] }
            let hue = Double((i - softSeries.count) % 24) / 24.0
            return Color(hue: hue, saturation: 0.5, brightness: 0.85)
        }
    }
}

/// 卡片容器修饰符：白底 + 圆角 + 细描边 + 极淡阴影（UsageBoard 风格）。
struct UBCard: ViewModifier {
    var padding: CGFloat = UB.Spacing.xxl
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(UB.Canvas.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous)
                    .stroke(UB.Canvas.separator.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 1, y: 1)
    }
}

extension View {
    /// 套用 UsageBoard 风格的卡片容器。
    func ubCard(padding: CGFloat = UB.Spacing.xxl) -> some View {
        modifier(UBCard(padding: padding))
    }
}
