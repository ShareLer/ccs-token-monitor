import Foundation
import Combine

/// 热力图显示模式。
enum HeatmapFitMode: String {
    case fit      // 缩小格子，完全显示本年不滑动
    case scroll   // 固定格子大小，可横向滑动
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

final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let dbPath = "dbPath"
        static let refreshInterval = "refreshIntervalMinutes"
        static let heatmapFitMode = "heatmapFitMode"
        static let screenshotDir = "screenshotDir"
        static let appearanceMode = "appearanceMode"
    }

    static var defaultDBPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".cc-switch/cc-switch.db")
    }

    @Published var dbPath: String {
        didSet { defaults.set(dbPath, forKey: Keys.dbPath) }
    }
    /// 允许值：5/10/15/30
    @Published var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshInterval) }
    }
    /// 热力图显示模式（默认 fit：完全显示本年）
    @Published var heatmapFitMode: HeatmapFitMode {
        didSet { defaults.set(heatmapFitMode.rawValue, forKey: Keys.heatmapFitMode) }
    }
    /// 截图保存目录（空 = 未设置，截图时提醒用户先设置）
    @Published var screenshotDir: String {
        didSet { defaults.set(screenshotDir, forKey: Keys.screenshotDir) }
    }
    /// 应用外观（默认跟随系统）
    @Published var appearanceMode: AppAppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }
    /// 当前系统外观是否为深色。用于“跟随系统”模式下给 SwiftUI 一个明确的 colorScheme。
    @Published private(set) var systemAppearanceIsDark: Bool

    init() {
        self.dbPath = defaults.string(forKey: Keys.dbPath) ?? SettingsStore.defaultDBPath
        let saved = defaults.integer(forKey: Keys.refreshInterval)
        self.refreshIntervalMinutes = saved == 0 ? 5 : saved
        self.heatmapFitMode = HeatmapFitMode(rawValue: defaults.string(forKey: Keys.heatmapFitMode) ?? "") ?? .fit
        self.screenshotDir = defaults.string(forKey: Keys.screenshotDir) ?? ""
        self.appearanceMode = AppAppearanceMode(rawValue: defaults.string(forKey: Keys.appearanceMode) ?? "") ?? .system
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
}
