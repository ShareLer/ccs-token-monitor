import Foundation
import Combine

@MainActor
final class BalanceStore: ObservableObject {
    static let disabledRuleID = "__disabled__"

    private let defaults: UserDefaults
    private enum Keys {
        static let rules = "balanceRules"
        static let modelRuleIDs = "balanceModelRuleIDs"
    }

    @Published var rules: [BalanceRule] {
        didSet { persistRules() }
    }

    @Published var modelRuleIDs: [String: String] {
        didSet { persistModelRuleIDs() }
    }

    @Published private(set) var balances: [String: ModelBalance] = [:]
    private let fetchBalance: @Sendable (BalanceRule, String, String) async -> ModelBalance

    init(defaults: UserDefaults = .standard,
         fetchBalance: @escaping @Sendable (BalanceRule, String, String) async -> ModelBalance = { rule, model, dbPath in
             await BalanceService.fetch(rule: rule, model: model, dbPath: dbPath)
         }) {
        self.defaults = defaults
        self.fetchBalance = fetchBalance
        if let data = defaults.data(forKey: Keys.rules),
           let decoded = try? JSONDecoder().decode([BalanceRule].self, from: data) {
            self.rules = BalanceStore.ensureBuiltins(in: decoded)
        } else {
            self.rules = [BalanceRule.deepseekBuiltin()]
        }

        if let data = defaults.data(forKey: Keys.modelRuleIDs),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.modelRuleIDs = decoded
        } else {
            self.modelRuleIDs = [:]
        }
    }

    func rule(for model: String) -> BalanceRule? {
        guard let id = modelRuleIDs[model] else { return nil }
        guard id != Self.disabledRuleID else { return nil }
        return rules.first { $0.id == id }
    }

    func effectiveRule(for model: String) -> BalanceRule? {
        if let id = modelRuleIDs[model] {
            guard id != Self.disabledRuleID else { return nil }
            return rules.first { $0.id == id }
        }
        if model.lowercased().contains("deepseek") {
            return rules.first { $0.id == BalanceRule.deepseekBuiltinID }
        }
        return nil
    }

    func balance(for model: String) -> ModelBalance? {
        balances[model]
    }

    func setRule(_ rule: BalanceRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    func deleteRule(id: String) {
        guard id != BalanceRule.deepseekBuiltinID else { return }
        rules.removeAll { $0.id == id }
        modelRuleIDs = modelRuleIDs.filter { $0.value != id }
    }

    func assign(ruleID: String?, to model: String) {
        if let ruleID, !ruleID.isEmpty {
            modelRuleIDs[model] = ruleID
        } else {
            modelRuleIDs.removeValue(forKey: model)
        }
    }

    func refresh(models: [String], dbPath: String) async {
        let uniqueModels = Array(Set(models))
        guard !uniqueModels.isEmpty else { return }

        var ruleRequests: [String: (rule: BalanceRule, models: [String])] = [:]

        for model in uniqueModels {
            guard let rule = effectiveRule(for: model) else {
                balances.removeValue(forKey: model)
                continue
            }

            balances[model] = ModelBalance(state: .loading, updatedAt: balances[model]?.updatedAt)
            if ruleRequests[rule.id] == nil {
                ruleRequests[rule.id] = (rule, [])
            }
            ruleRequests[rule.id]?.models.append(model)
        }

        let fetchBalance = self.fetchBalance
        await withTaskGroup(of: [(String, ModelBalance)].self) { group in
            for request in ruleRequests.values {
                guard let representativeModel = request.models.first else { continue }
                group.addTask {
                    let result = await fetchBalance(request.rule, representativeModel, dbPath)
                    return request.models.map { ($0, result) }
                }
            }

            for await results in group {
                for (model, balance) in results {
                    balances[model] = balance
                }
            }
        }
    }

    func refresh(model: String, dbPath: String) async {
        await refresh(models: [model], dbPath: dbPath)
    }

    private static func ensureBuiltins(in rules: [BalanceRule]) -> [BalanceRule] {
        if rules.contains(where: { $0.id == BalanceRule.deepseekBuiltinID }) {
            return rules
        }
        return [BalanceRule.deepseekBuiltin()] + rules
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Keys.rules)
        }
    }

    private func persistModelRuleIDs() {
        if let data = try? JSONEncoder().encode(modelRuleIDs) {
            defaults.set(data, forKey: Keys.modelRuleIDs)
        }
    }
}
