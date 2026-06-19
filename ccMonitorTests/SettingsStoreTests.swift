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
}
