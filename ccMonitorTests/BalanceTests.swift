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

    func test_validatePythonSyntax_acceptsValidScript() async throws {
        try await BalanceService.validatePythonSyntax("print(1)")
    }

    func test_validatePythonSyntax_rejectsInvalidScript() async {
        do {
            try await BalanceService.validatePythonSyntax("def bad(:\n    pass")
            XCTFail("Expected syntax validation to fail")
        } catch let error as BalanceExecutionError {
            guard case .script = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_validateJavaScriptTemplate_acceptsRequestExtractorTemplate() throws {
        try BalanceService.validateJavaScriptTemplate(BalanceRule.javascriptDefaultScript,
                                                      baseUrl: "https://api.example.com",
                                                      apiKey: "sk-test")
    }

    func test_validateJavaScriptTemplate_rejectsMissingExtractor() {
        XCTAssertThrowsError(try BalanceService.validateJavaScriptTemplate("""
        ({
          request: { url: "{{baseUrl}}/v1/usage", method: "GET" }
        })
        """))
    }

    func test_parseBalanceValue_acceptsRemainingAndUnit() throws {
        let parsed = try BalanceService.parseBalanceValue([
            "remaining": 12.3,
            "unit": "USD"
        ])

        XCTAssertEqual(parsed.0, 12.3, accuracy: 0.0001)
        XCTAssertEqual(parsed.1, "USD")
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

        let apiKey = DeepSeekCredentialResolver.parse(settingsConfig: config)

        XCTAssertEqual(apiKey, "sk-test-claude")
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

        let apiKey = DeepSeekCredentialResolver.parse(settingsConfig: config)

        XCTAssertEqual(apiKey, "sk-test-codex")
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

    @MainActor
    func test_refresh_reusesDeepSeekBalanceForModelsWithSameRule() async {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calls = CallRecorder()
        let store = BalanceStore(defaults: defaults) { rule, model, _ in
            await calls.record(ruleID: rule.id, model: model)
            return ModelBalance(state: .value(12, currency: rule.currency), updatedAt: Date())
        }

        await store.refresh(models: ["deepseek-v4-pro", "deepseek-v4-flash"], dbPath: "/tmp/test.db")

        let recorded = await calls.values
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.ruleID, BalanceRule.deepseekBuiltinID)
        XCTAssertEqual(store.balance(for: "deepseek-v4-pro")?.state, .value(12, currency: "CNY"))
        XCTAssertEqual(store.balance(for: "deepseek-v4-flash")?.state, .value(12, currency: "CNY"))
    }

    @MainActor
    func test_refresh_reusesPythonBalanceForModelsWithSameRule() async {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rule = BalanceRule(id: "python.shared", name: "Python", kind: .python, currency: "CNY", script: "print(1)")
        defaults.set(try! JSONEncoder().encode([rule]), forKey: "balanceRules")
        let calls = CallRecorder()
        let store = BalanceStore(defaults: defaults) { rule, model, _ in
            await calls.record(ruleID: rule.id, model: model)
            return ModelBalance(state: .value(9, currency: rule.currency), updatedAt: Date())
        }
        store.assign(ruleID: rule.id, to: "model-a")
        store.assign(ruleID: rule.id, to: "model-b")

        await store.refresh(models: ["model-a", "model-b"], dbPath: "/tmp/test.db")

        let recorded = await calls.values
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.ruleID, rule.id)
        XCTAssertEqual(store.balance(for: "model-a")?.state, .value(9, currency: "CNY"))
        XCTAssertEqual(store.balance(for: "model-b")?.state, .value(9, currency: "CNY"))
    }

    @MainActor
    func test_refreshRule_storesBalanceByRule() async {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rule = BalanceRule(id: "python.direct", name: "Python", kind: .python, currency: "CNY", script: "print(1)")
        defaults.set(try! JSONEncoder().encode([rule]), forKey: "balanceRules")
        let store = BalanceStore(defaults: defaults) { rule, _, _ in
            ModelBalance(state: .value(18, currency: rule.currency), updatedAt: Date())
        }

        await store.refresh(ruleID: rule.id, dbPath: "/tmp/test.db")

        XCTAssertEqual(store.balance(forRuleID: rule.id)?.state, .value(18, currency: "CNY"))
    }

    private func makeDefaults() -> (String, UserDefaults) {
        let name = "ccMonitor.balanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (name, defaults)
    }
}

private actor CallRecorder {
    private(set) var values: [(ruleID: String, model: String)] = []

    func record(ruleID: String, model: String) {
        values.append((ruleID, model))
    }
}
