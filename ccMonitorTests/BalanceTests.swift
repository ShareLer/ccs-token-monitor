import XCTest
@testable import ccMonitor

final class BalanceTests: XCTestCase {
    func test_parseAmount_acceptsPlainNumber() throws {
        XCTAssertEqual(try BalanceService.parseAmount("12.34\n"), 12.34, accuracy: 0.0001)
    }

    func test_parseAmount_acceptsJSONAmount() throws {
        XCTAssertEqual(try BalanceService.parseAmount(#"{"amount":"45.67"}"#), 45.67, accuracy: 0.0001)
        XCTAssertEqual(try BalanceService.parseAmount(#"{"balance":89.1}"#), 89.1, accuracy: 0.0001)
        XCTAssertEqual(try BalanceService.parseAmount(#"{"remaining":3}"#), 3, accuracy: 0.0001)
    }

    func test_parseAmount_rejectsInvalidOutput() {
        XCTAssertThrowsError(try BalanceService.parseAmount("not-a-number"))
    }

    func test_deepSeekCredentialResolver_parsesClaudeProviderConfig() {
        let config = """
        {
          "env": {
            "ANTHROPIC_AUTH_TOKEN": " sk-test-claude ",
            "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": "Deepseek-v4-pro"
          }
        }
        """

        let credentials = DeepSeekCredentialResolver.parse(settingsConfig: config)

        XCTAssertEqual(credentials?.apiKey, "sk-test-claude")
        XCTAssertEqual(credentials?.baseURL, "https://api.deepseek.com")
    }

    func test_deepSeekCredentialResolver_parsesCodexProviderConfig() {
        let config = """
        {
          "auth": {
            "OPENAI_API_KEY": "sk-test-codex"
          },
          "config": "model_provider = \\"custom\\"\\nmodel = \\"deepseek-v4-flash\\"\\n[model_providers.deepseek]\\nbase_url = \\"https://api.deepseek.com\\""
        }
        """

        let credentials = DeepSeekCredentialResolver.parse(settingsConfig: config)

        XCTAssertEqual(credentials?.apiKey, "sk-test-codex")
        XCTAssertEqual(credentials?.baseURL, "https://api.deepseek.com")
    }

    @MainActor
    func test_balanceStoreAddsDeepSeekBuiltin() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = BalanceRule(id: "custom", name: "Custom", kind: .python)
        defaults.set(try! JSONEncoder().encode([custom]), forKey: "balanceRules")

        let store = BalanceStore(defaults: defaults)

        XCTAssertTrue(store.rules.contains { $0.id == BalanceRule.deepseekBuiltinID })
        XCTAssertTrue(store.rules.contains { $0.id == "custom" })
    }

    @MainActor
    func test_effectiveRule_autoDetectsDeepSeekModel() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BalanceStore(defaults: defaults)

        let rule = store.effectiveRule(for: "deepseek-v4-pro")

        XCTAssertEqual(rule?.id, BalanceRule.deepseekBuiltinID)
    }

    @MainActor
    func test_effectiveRule_canDisableAutoDeepSeek() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BalanceStore(defaults: defaults)

        store.assign(ruleID: BalanceStore.disabledRuleID, to: "deepseek-v4-pro")

        XCTAssertNil(store.effectiveRule(for: "deepseek-v4-pro"))
    }

    private func makeDefaults() -> (String, UserDefaults) {
        let name = "ccMonitor.balanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (name, defaults)
    }
}
