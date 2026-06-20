import XCTest
@testable import ccMonitor

final class SettingsStoreTests: XCTestCase {
    func test_backgroundStyleDefaultsToSolid() {
        let name = "ccMonitor.settingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.backgroundStyle, .solid)
    }

    func test_backgroundStylePersistsGlass() {
        let name = "ccMonitor.settingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        store.backgroundStyle = .glass

        XCTAssertEqual(SettingsStore(defaults: defaults).backgroundStyle, .glass)
    }

    func test_modelUsageDisplaySettingsDefaultToTopFiveByTotalTokens() {
        let name = "ccMonitor.settingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.modelUsageDisplayCount, 5)
        XCTAssertEqual(store.modelUsageSortMetric, .totalTokens)
    }

    func test_modelUsageDisplaySettingsPersist() {
        let name = "ccMonitor.settingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let store = SettingsStore(defaults: defaults)
        store.modelUsageDisplayCount = 8
        store.modelUsageSortMetric = .cost

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.modelUsageDisplayCount, 8)
        XCTAssertEqual(reloaded.modelUsageSortMetric, .cost)
    }

    func test_modelUsageDisplayCountClampsSavedValues() {
        let name = "ccMonitor.settingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(99, forKey: "modelUsageDisplayCount")
        XCTAssertEqual(SettingsStore(defaults: defaults).modelUsageDisplayCount, 10)

        defaults.set(0, forKey: "modelUsageDisplayCount")
        XCTAssertEqual(SettingsStore(defaults: defaults).modelUsageDisplayCount, 1)
    }

    func test_refreshIntervalNormalizesRemovedTenMinuteValue() {
        let name = "ccMonitor.settingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(10, forKey: "refreshIntervalMinutes")

        XCTAssertEqual(SettingsStore(defaults: defaults).refreshIntervalMinutes, 15)
    }
}
