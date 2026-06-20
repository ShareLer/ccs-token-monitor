import SwiftUI
import AppKit

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
        static let surface: CGFloat = 8
        static let control: CGFloat = 5
        static let pill: CGFloat = 999
    }

    enum Font {
        static let popoverTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let cardTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let itemTitle = SwiftUI.Font.system(size: 12, weight: .medium)
        static let sectionTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 12.5)
        static let label = SwiftUI.Font.system(size: 11.5)
        static let caption = SwiftUI.Font.system(size: 11)
        static let summaryBig = SwiftUI.Font.system(size: 26, weight: .bold).monospacedDigit()
        static let metricBig = SwiftUI.Font.system(size: 14, weight: .semibold).monospacedDigit()
        static let countdown = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()
    }

    enum Canvas {
        /// popover 根背景（系统语义色，跟随浅色/深色外观）
        static let canvasBackground = Color(nsColor: .controlBackgroundColor)
        /// 卡片背景（纯白/深色模式自适应）
        static let cardBackground = Color(nsColor: .textBackgroundColor)
        /// 顶栏背景
        static let barBackground = Color(nsColor: .windowBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)

        enum LineStyle {
            case hairline
            case divider
            case outline
            case grid
        }

        /// 分割线层级：浅色保持克制，深色提高对比度，避免系统 separator 再叠透明度后过弱。
        static func lineColor(_ style: LineStyle, for colorScheme: ColorScheme) -> Color {
            let opacity: Double
            if colorScheme == .dark {
                switch style {
                case .hairline: opacity = 0.18
                case .divider: opacity = 0.24
                case .outline: opacity = 0.28
                case .grid: opacity = 0.16
                }
            } else {
                switch style {
                case .hairline: opacity = 0.08
                case .divider: opacity = 0.12
                case .outline: opacity = 0.10
                case .grid: opacity = 0.08
                }
            }
            return Color.primary.opacity(opacity)
        }

        static func lineWidth(_ style: LineStyle, for colorScheme: ColorScheme) -> CGFloat {
            switch style {
            case .outline:
                return colorScheme == .dark ? 0.8 : 0.5
            case .divider:
                return colorScheme == .dark ? 0.7 : 0.5
            case .hairline, .grid:
                return 0.5
            }
        }
    }

    enum Glass {
        static let primary = Color(hex: 0x2196F3)
        static let chartBlue = Color(hex: 0x5B8FF9)
        static let positive = Color(hex: 0x2FA36F)
        static let warning = Color(hex: 0xF59E0B)

        static func canvasTint(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.black.opacity(0.06)
                : Color.white.opacity(0.03)
        }

        static func cardFill(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.black.opacity(0.15)
                : Color.white.opacity(0.14)
        }

        static func cardFillStrong(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.black.opacity(0.20)
                : Color.white.opacity(0.18)
        }

        static func controlFill(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.white.opacity(0.15)
                : Color.gray.opacity(0.18)
        }

        static func border(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.white.opacity(0.24)
                : Color.white.opacity(0.40)
        }

        static func subtleBorder(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.white.opacity(0.18)
                : Color.white.opacity(0.34)
        }

        static func shadow(for colorScheme: ColorScheme) -> Color {
            Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10)
        }

        static func tooltipFill(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.black.opacity(0.66)
                : Color.black.opacity(0.76)
        }

    }

    enum Palette {
        static let accent = Color(hex: 0x2196F3)        // 主蓝
        static let cache = Color(hex: 0xFFC107)         // 缓存（琥珀）
        static let cost = Color(hex: 0x4CAF50)          // 成本（绿）
        static let balance = Color(hex: 0x00897B)       // 余额（青绿）

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

        /// 玻璃模式下的图表色：沿用项目主蓝，辅以更饱和的少量辅助色。
        static let glassSeries: [Color] = [
            UB.Glass.primary,
            UB.Glass.positive,
            UB.Glass.warning,
            UB.Glass.chartBlue,
            Color(hex: 0x8B5CF6),
            Color(hex: 0xEC4899),
            Color(hex: 0x14B8A6),
            Color(hex: 0xEF4444),
        ]
        static func glassSeriesColor(_ i: Int) -> Color {
            if i < glassSeries.count { return glassSeries[i] }
            let hue = Double((i - glassSeries.count) % 18) / 18.0
            return Color(hue: hue, saturation: 0.72, brightness: 0.90)
        }
    }
}

/// 卡片容器修饰符：白底 + 圆角 + 细描边 + 极淡阴影（UsageBoard 风格）。
struct UBCard: ViewModifier {
    var padding: CGFloat = UB.Spacing.xxl
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appBackgroundStyle) private var appBackgroundStyle

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous)
                    .fill(cardFill)
            }
            .clipShape(RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UB.Radius.card, style: .continuous)
                    .stroke(
                        outlineColor,
                        lineWidth: outlineWidth
                    )
            )
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var cardFill: AnyShapeStyle {
        switch appBackgroundStyle {
        case .solid:
            return AnyShapeStyle(UB.Canvas.cardBackground)
        case .glass:
            return AnyShapeStyle(UB.Glass.cardFill(for: colorScheme))
        }
    }

    private var outlineColor: Color {
        if appBackgroundStyle == .glass {
            return UB.Glass.border(for: colorScheme)
        }
        return UB.Canvas.lineColor(.outline, for: colorScheme)
    }

    private var outlineWidth: CGFloat {
        if appBackgroundStyle == .glass {
            return colorScheme == .dark ? 0.9 : 0.7
        }
        return UB.Canvas.lineWidth(.outline, for: colorScheme)
    }

    private var shadowColor: Color {
        if appBackgroundStyle == .glass {
            return UB.Glass.shadow(for: colorScheme)
        }
        return Color.black.opacity(0.02)
    }

    private var shadowRadius: CGFloat {
        appBackgroundStyle == .glass ? 5 : 1
    }

    private var shadowY: CGFloat {
        appBackgroundStyle == .glass ? 6 : 1
    }
}

struct UBDivider: View {
    enum Orientation {
        case horizontal
        case vertical
    }

    var orientation: Orientation = .horizontal
    var style: UB.Canvas.LineStyle = .divider
    var length: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appBackgroundStyle) private var appBackgroundStyle

    var body: some View {
        let lineWidth = UB.Canvas.lineWidth(style, for: colorScheme)
        Rectangle()
            .fill(lineColor)
            .frame(
                width: orientation == .vertical ? lineWidth : length,
                height: orientation == .horizontal ? lineWidth : length
            )
    }

    private var lineColor: Color {
        if appBackgroundStyle == .glass {
            switch style {
            case .hairline, .grid:
                return UB.Glass.subtleBorder(for: colorScheme)
            case .divider, .outline:
                return UB.Glass.border(for: colorScheme)
            }
        }
        return UB.Canvas.lineColor(style, for: colorScheme)
    }
}

extension View {
    /// 套用 UsageBoard 风格的卡片容器。
    func ubCard(padding: CGFloat = UB.Spacing.xxl) -> some View {
        modifier(UBCard(padding: padding))
    }

    @ViewBuilder
    func appBackground(_ style: AppBackgroundStyle) -> some View {
        switch style {
        case .solid:
            background(UB.Canvas.canvasBackground)
        case .glass:
            modifier(AppGlassBackground())
        }
    }
}

private struct AppGlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(UB.Glass.canvasTint(for: colorScheme))
            }
        }
    }
}

private struct AppBackgroundStyleKey: EnvironmentKey {
    static let defaultValue: AppBackgroundStyle = .solid
}

extension EnvironmentValues {
    var appBackgroundStyle: AppBackgroundStyle {
        get { self[AppBackgroundStyleKey.self] }
        set { self[AppBackgroundStyleKey.self] = newValue }
    }
}

extension AppAppearanceMode {
    func preferredColorScheme(systemIsDark: Bool) -> ColorScheme {
        switch self {
        case .system: return systemIsDark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }

    func nsAppearance(systemIsDark: Bool) -> NSAppearance? {
        switch preferredColorScheme(systemIsDark: systemIsDark) {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        @unknown default: return NSAppearance(named: .aqua)
        }
    }
}
