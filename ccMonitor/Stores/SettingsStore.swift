import Foundation
import Combine

/// 热力图显示模式。
enum HeatmapFitMode: String {
    case fit      // 缩小格子，完全显示本年不滑动
    case scroll   // 固定格子大小，可横向滑动
}

final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let dbPath = "dbPath"
        static let refreshInterval = "refreshIntervalMinutes"
        static let heatmapFitMode = "heatmapFitMode"
        static let screenshotDir = "screenshotDir"
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

    init() {
        self.dbPath = defaults.string(forKey: Keys.dbPath) ?? SettingsStore.defaultDBPath
        let saved = defaults.integer(forKey: Keys.refreshInterval)
        self.refreshIntervalMinutes = saved == 0 ? 5 : saved
        self.heatmapFitMode = HeatmapFitMode(rawValue: defaults.string(forKey: Keys.heatmapFitMode) ?? "") ?? .fit
        self.screenshotDir = defaults.string(forKey: Keys.screenshotDir) ?? ""
    }
}
