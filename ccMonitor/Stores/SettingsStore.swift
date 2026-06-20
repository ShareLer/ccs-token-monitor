import Foundation
import Combine

/// 热力图显示模式。
enum HeatmapFitMode: String {
    case fit      // 缩小格子，完全显示本年不滑动
    case scroll   // 固定格子大小，可横向滑动
}

/// 近30日趋势图展示模式。
enum TrendChartDisplayMode: String, CaseIterable, Identifiable {
    case bar
    case line

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bar: return "柱状图"
        case .line: return "折线图"
        }
    }
}

/// 应用外观模式。
enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var next: AppAppearanceMode {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }
}

/// 应用背景样式。与浅色/深色外观独立，毛玻璃会跟随当前外观呈现亮/暗材质。
enum AppBackgroundStyle: String, CaseIterable, Identifiable {
    case solid
    case glass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solid: return "实色"
        case .glass: return "毛玻璃"
        }
    }
}

final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private enum Keys {
        static let dbPath = "dbPath"
        static let refreshInterval = "refreshIntervalMinutes"
        static let heatmapFitMode = "heatmapFitMode"
        static let trendChartDisplayMode = "trendChartDisplayMode"
        static let screenshotDir = "screenshotDir"
        static let appearanceMode = "appearanceMode"
        static let backgroundStyle = "backgroundStyle"
        static let modelUsageDisplayCount = "modelUsageDisplayCount"
        static let modelUsageSortMetric = "modelUsageSortMetric"
    }

    static let minModelUsageDisplayCount = 1
    static let maxModelUsageDisplayCount = 10
    static let refreshIntervalOptions = [5, 15, 30]

    static var defaultDBPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".cc-switch/cc-switch.db")
    }

    @Published var dbPath: String {
        didSet { defaults.set(dbPath, forKey: Keys.dbPath) }
    }
    /// 允许值：5/15/30
    @Published var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshInterval) }
    }
    /// 热力图显示模式（默认 fit：完全显示本年）
    @Published var heatmapFitMode: HeatmapFitMode {
        didSet { defaults.set(heatmapFitMode.rawValue, forKey: Keys.heatmapFitMode) }
    }
    /// 近30日趋势图展示模式（默认柱状图，保持现有行为）
    @Published var trendChartDisplayMode: TrendChartDisplayMode {
        didSet { defaults.set(trendChartDisplayMode.rawValue, forKey: Keys.trendChartDisplayMode) }
    }
    /// 截图保存目录（空 = 未设置，截图时提醒用户先设置）
    @Published var screenshotDir: String {
        didSet { defaults.set(screenshotDir, forKey: Keys.screenshotDir) }
    }
    /// 应用外观（默认跟随系统）
    @Published var appearanceMode: AppAppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }
    /// 应用背景样式（默认实色，保持现有行为）
    @Published var backgroundStyle: AppBackgroundStyle {
        didSet { defaults.set(backgroundStyle.rawValue, forKey: Keys.backgroundStyle) }
    }
    /// 模型用量明细展示的模型数量，默认 5，设置页限制为 1...10。
    @Published var modelUsageDisplayCount: Int {
        didSet { defaults.set(modelUsageDisplayCount, forKey: Keys.modelUsageDisplayCount) }
    }
    /// 模型用量明细 Top N 排序口径，默认总 Token 量。
    @Published var modelUsageSortMetric: ModelUsageSortMetric {
        didSet { defaults.set(modelUsageSortMetric.rawValue, forKey: Keys.modelUsageSortMetric) }
    }
    /// 当前系统外观是否为深色。用于“跟随系统”模式下给 SwiftUI 一个明确的 colorScheme。
    @Published private(set) var systemAppearanceIsDark: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.dbPath = defaults.string(forKey: Keys.dbPath) ?? SettingsStore.defaultDBPath
        let saved = defaults.integer(forKey: Keys.refreshInterval)
        self.refreshIntervalMinutes = Self.normalizedRefreshInterval(saved)
        self.heatmapFitMode = HeatmapFitMode(rawValue: defaults.string(forKey: Keys.heatmapFitMode) ?? "") ?? .fit
        self.trendChartDisplayMode = TrendChartDisplayMode(rawValue: defaults.string(forKey: Keys.trendChartDisplayMode) ?? "") ?? .bar
        self.screenshotDir = defaults.string(forKey: Keys.screenshotDir) ?? ""
        self.appearanceMode = AppAppearanceMode(rawValue: defaults.string(forKey: Keys.appearanceMode) ?? "") ?? .system
        self.backgroundStyle = AppBackgroundStyle(rawValue: defaults.string(forKey: Keys.backgroundStyle) ?? "") ?? .solid
        let savedModelUsageCount = defaults.object(forKey: Keys.modelUsageDisplayCount) as? Int ?? 5
        self.modelUsageDisplayCount = Self.clampedModelUsageDisplayCount(savedModelUsageCount)
        self.modelUsageSortMetric = ModelUsageSortMetric(rawValue: defaults.string(forKey: Keys.modelUsageSortMetric) ?? "") ?? .totalTokens
        self.systemAppearanceIsDark = SettingsStore.currentSystemAppearanceIsDark()
    }

    func cycleAppearanceMode() {
        appearanceMode = appearanceMode.next
    }

    func refreshSystemAppearance() {
        systemAppearanceIsDark = SettingsStore.currentSystemAppearanceIsDark()
    }

    static func currentSystemAppearanceIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func clampedModelUsageDisplayCount(_ count: Int) -> Int {
        min(max(count, minModelUsageDisplayCount), maxModelUsageDisplayCount)
    }

    static func normalizedRefreshInterval(_ minutes: Int) -> Int {
        if refreshIntervalOptions.contains(minutes) {
            return minutes
        }
        if minutes == 0 {
            return refreshIntervalOptions[0]
        }

        return refreshIntervalOptions.min { lhs, rhs in
            let lhsDistance = abs(lhs - minutes)
            let rhsDistance = abs(rhs - minutes)
            if lhsDistance == rhsDistance {
                return lhs > rhs
            }
            return lhsDistance < rhsDistance
        } ?? refreshIntervalOptions[0]
    }
}
