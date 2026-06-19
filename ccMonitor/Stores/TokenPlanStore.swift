import Foundation
import Combine

@MainActor
final class TokenPlanStore: ObservableObject {
    private let defaults: UserDefaults
    private let fetchQuota: @Sendable (TokenPlanConfig) async throws -> TokenPlanQuota

    private enum Keys {
        static let config = "tokenPlanConfig"
        static let configs = "tokenPlanConfigs"
    }

    @Published var configs: [TokenPlanConfig] {
        didSet { persistConfigs() }
    }

    @Published private(set) var quotas: [TokenPlanConfigID: TokenPlanQuota] = [:]
    @Published private(set) var states: [TokenPlanConfigID: TokenPlanLoadState] = [:]

    init(defaults: UserDefaults = .standard,
         fetchQuota: @escaping @Sendable (TokenPlanConfig) async throws -> TokenPlanQuota = { config in
             try await TokenPlanService.fetch(config: config)
         }) {
        self.defaults = defaults
        self.fetchQuota = fetchQuota
        self.configs = TokenPlanStore.loadConfigs(defaults: defaults)
    }

    var shouldDisplay: Bool {
        configs.contains { $0.isConfigured }
    }

    var activeConfigs: [TokenPlanConfig] {
        configs.filter(\.isConfigured)
    }

    func config(for id: TokenPlanConfigID) -> TokenPlanConfig {
        configs.first { $0.id == id } ?? TokenPlanConfig(id: id)
    }

    func quota(for id: TokenPlanConfigID) -> TokenPlanQuota? {
        quotas[id]
    }

    func state(for id: TokenPlanConfigID) -> TokenPlanLoadState {
        states[id] ?? .idle
    }

    func setConfig(_ config: TokenPlanConfig) {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
            configs.sort { lhs, rhs in
                let lhsIndex = TokenPlanConfigID.allCases.firstIndex(of: lhs.id) ?? 0
                let rhsIndex = TokenPlanConfigID.allCases.firstIndex(of: rhs.id) ?? 0
                return lhsIndex < rhsIndex
            }
        }
    }

    func refresh() async {
        let active = activeConfigs
        let inactiveIDs = Set(TokenPlanConfigID.allCases).subtracting(active.map(\.id))
        for id in inactiveIDs {
            quotas[id] = nil
            states[id] = .idle
        }
        guard !active.isEmpty else {
            return
        }

        for config in active {
            states[config.id] = .loading
        }

        let fetchQuota = self.fetchQuota
        await withTaskGroup(of: (TokenPlanConfigID, Result<TokenPlanQuota, Error>).self) { group in
            for config in active {
                group.addTask {
                    do {
                        return (config.id, .success(try await fetchQuota(config)))
                    } catch {
                        return (config.id, .failure(error))
                    }
                }
            }

            for await (id, result) in group {
                switch result {
                case .success(let quota):
                    quotas[id] = quota
                    states[id] = .loaded
                case .failure(let error):
                    states[id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    private static func loadConfigs(defaults: UserDefaults) -> [TokenPlanConfig] {
        if let data = defaults.data(forKey: Keys.configs),
           let decoded = try? JSONDecoder().decode([TokenPlanConfig].self, from: data) {
            return normalized(decoded)
        }

        if let data = defaults.data(forKey: Keys.config),
           let legacy = try? JSONDecoder().decode(TokenPlanConfig.self, from: data) {
            return migrateLegacyConfig(legacy)
        }

        return normalized([])
    }

    private static func migrateLegacyConfig(_ legacy: TokenPlanConfig) -> [TokenPlanConfig] {
        var configs = normalized([])
        guard let provider = legacy.detectedProvider else { return configs }
        let id = TokenPlanConfigID.from(provider: provider)
        if let index = configs.firstIndex(where: { $0.id == id }) {
            configs[index] = TokenPlanConfig(id: id,
                                             enabled: legacy.enabled,
                                             baseUrl: legacy.baseUrl,
                                             apiKey: legacy.apiKey)
        }
        return configs
    }

    private static func normalized(_ configs: [TokenPlanConfig]) -> [TokenPlanConfig] {
        TokenPlanConfigID.allCases.map { id in
            configs.first { $0.id == id } ?? TokenPlanConfig(id: id)
        }
    }

    private func persistConfigs() {
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: Keys.configs)
        }
    }
}
