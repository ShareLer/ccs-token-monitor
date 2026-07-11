import Foundation
import Combine

@MainActor
final class TokenPlanStore: ObservableObject {
    private let defaults: UserDefaults
    private let fetchQuota: @Sendable (TokenPlanConfig) async throws -> TokenPlanQuota
    private let log = AppLog("TokenPlan")
    private var codexLoginTask: Task<Void, Never>?
    private var codexLoginGeneration = 0
    private var refreshGenerations: [TokenPlanConfigID: Int] = [:]

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
        log.info("config updated id=\(config.id.rawValue) enabled=\(config.enabled) configured=\(config.isConfigured)")
    }

    func setEnabled(_ id: TokenPlanConfigID, enabled: Bool) {
        var config = config(for: id)
        config.enabled = enabled
        setConfig(config)

        if id == .codex {
            if enabled {
                startCodexLogin(force: false)
            } else {
                codexLoginGeneration += 1
                codexLoginTask?.cancel()
                codexLoginTask = nil
                Task { await refresh() }
            }
        } else if !enabled {
            Task { await refresh() }
        }
    }

    func startCodexLogin(force: Bool = true) {
        codexLoginGeneration += 1
        refreshGenerations[.codex, default: 0] += 1
        let generation = codexLoginGeneration
        codexLoginTask?.cancel()
        codexLoginTask = Task { [weak self] in
            await self?.loginCodex(force: force, generation: generation)
        }
    }

    private func loginCodex(force: Bool, generation: Int) async {
        let id = TokenPlanConfigID.codex
        guard config(for: id).enabled, codexLoginGeneration == generation else { return }
        states[id] = .loading
        defer {
            if codexLoginGeneration == generation {
                codexLoginTask = nil
            }
        }
        do {
            let account: CodexAccountConfig
            if !force, let stored = CodexOAuthService.storedAccount() {
                account = stored
            } else {
                account = try await CodexOAuthService.login()
            }
            try Task.checkCancellation()
            guard config(for: id).enabled, codexLoginGeneration == generation else {
                return
            }
            var config = config(for: id)
            config.codexAccount = account
            setConfig(config)
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            guard config(for: id).enabled, codexLoginGeneration == generation else {
                return
            }
            states[id] = .failed(error.localizedDescription)
            log.error("Codex login failed: \(error.localizedDescription)")
        }
    }

    func refresh() async {
        let active = activeConfigs
        log.info("refresh started active=\(active.map(\.id.rawValue).joined(separator: ","))")
        let inactiveIDs = Set(TokenPlanConfigID.allCases).subtracting(active.map(\.id))
        for id in inactiveIDs {
            refreshGenerations[id, default: 0] += 1
            quotas[id] = nil
            states[id] = .idle
        }
        guard !active.isEmpty else {
            return
        }

        for config in active {
            refreshGenerations[config.id, default: 0] += 1
            states[config.id] = .loading
        }
        let submittedGenerations = Dictionary(uniqueKeysWithValues: active.map {
            ($0.id, refreshGenerations[$0.id] ?? 0)
        })

        let fetchQuota = self.fetchQuota
        await withTaskGroup(of: (TokenPlanConfig, Int, Result<TokenPlanQuota, Error>).self) { group in
            for config in active {
                let generation = submittedGenerations[config.id] ?? 0
                group.addTask {
                    do {
                        return (config, generation, .success(try await fetchQuota(config)))
                    } catch {
                        return (config, generation, .failure(error))
                    }
                }
            }

            for await (submittedConfig, submittedGeneration, result) in group {
                let id = submittedConfig.id
                guard submittedGeneration == refreshGenerations[id],
                      config(for: id) == submittedConfig else {
                    continue
                }
                switch result {
                case .success(let quota):
                    quotas[id] = quota
                    states[id] = .loaded
                    if id == .codex,
                       let planType = quota.planLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !planType.isEmpty {
                        var config = config(for: id)
                        if config.codexAccount?.planType != planType {
                            config.codexAccount?.planType = planType
                            setConfig(config)
                        }
                    }
                    log.info("refresh loaded id=\(id.rawValue) tiers=\(quota.tiers.count)")
                case .failure(let error):
                    states[id] = .failed(error.localizedDescription)
                    log.error("refresh failed id=\(id.rawValue): \(error.localizedDescription)")
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
