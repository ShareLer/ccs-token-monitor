import Foundation
import Combine

final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let dbPath = "dbPath"
        static let refreshInterval = "refreshIntervalMinutes"
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

    init() {
        self.dbPath = defaults.string(forKey: Keys.dbPath) ?? SettingsStore.defaultDBPath
        let saved = defaults.integer(forKey: Keys.refreshInterval)
        self.refreshIntervalMinutes = saved == 0 ? 5 : saved
    }
}
