import Foundation

struct DeepSeekCredentialResolver {
    private let dbPath: String

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    func resolve() throws -> (baseURL: String, apiKey: String) {
        let db = try SQLiteDatabase(path: dbPath, readonly: true)
        defer { db.close() }

        var candidates: [(baseURL: String, apiKey: String, score: Int)] = []
        try db.query(Self.deepSeekProviderSQL) { row in
            guard let settings = row.string(2),
                  let candidate = Self.parse(settingsConfig: settings) else {
                return
            }

            let appType = row.string(0)?.lowercased() ?? ""
            let name = row.string(1)?.lowercased() ?? ""
            let score = Self.score(appType: appType, name: name, baseURL: candidate.baseURL)
            candidates.append((candidate.baseURL, candidate.apiKey, score))
        }

        guard let best = candidates.sorted(by: { $0.score > $1.score }).first else {
            throw BalanceExecutionError.missingAPIKey
        }
        return (best.baseURL, best.apiKey)
    }

    static func parse(settingsConfig: String) -> (baseURL: String, apiKey: String)? {
        guard let data = settingsConfig.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let keyPaths = [
            ["env", "ANTHROPIC_AUTH_TOKEN"],
            ["env", "ANTHROPIC_API_KEY"],
            ["auth", "OPENAI_API_KEY"],
            ["env", "OPENAI_API_KEY"],
            ["api_key"],
            ["apiKey"]
        ]
        guard let apiKey = firstString(in: object, keyPaths: keyPaths) else {
            return nil
        }

        let baseURL = firstString(in: object, keyPaths: [
            ["env", "ANTHROPIC_BASE_URL"],
            ["env", "OPENAI_BASE_URL"],
            ["base_url"],
            ["baseURL"]
        ]) ?? "https://api.deepseek.com"

        guard isDeepSeekProvider(object: object, baseURL: baseURL) else {
            return nil
        }

        return (normalizedBaseURL(baseURL), apiKey)
    }

    private static let deepSeekProviderSQL = """
        SELECT app_type, name, settings_config
        FROM providers
        WHERE lower(name) LIKE '%deepseek%'
           OR lower(settings_config) LIKE '%deepseek%'
        """

    private static func firstString(in object: [String: Any], keyPaths: [[String]]) -> String? {
        for keyPath in keyPaths {
            guard let value = value(in: object, keyPath: keyPath) else { continue }
            let string: String?
            if let value = value as? String {
                string = value
            } else if let value = value as? NSNumber {
                string = value.stringValue
            } else {
                string = nil
            }
            if let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func value(in object: [String: Any], keyPath: [String]) -> Any? {
        var current: Any = object
        for key in keyPath {
            guard let dict = current as? [String: Any],
                  let next = dict[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    private static func isDeepSeekProvider(object: [String: Any], baseURL: String) -> Bool {
        if baseURL.lowercased().contains("deepseek") {
            return true
        }

        if let config = firstString(in: object, keyPaths: [["config"]]),
           config.lowercased().contains("deepseek") {
            return true
        }

        let modelKeys = [
            ["env", "ANTHROPIC_MODEL"],
            ["env", "ANTHROPIC_DEFAULT_HAIKU_MODEL"],
            ["env", "ANTHROPIC_DEFAULT_SONNET_MODEL"],
            ["env", "ANTHROPIC_DEFAULT_OPUS_MODEL"]
        ]
        return firstString(in: object, keyPaths: modelKeys)?.lowercased().contains("deepseek") == true
    }

    private static func normalizedBaseURL(_ baseURL: String) -> String {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("/anthropic") {
            normalized.removeLast("/anthropic".count)
        }
        return normalized.isEmpty ? "https://api.deepseek.com" : normalized
    }

    private static func score(appType: String, name: String, baseURL: String) -> Int {
        var score = 0
        if name.contains("deepseek") { score += 10 }
        if baseURL.lowercased().contains("api.deepseek.com") { score += 5 }
        if appType == "codex" { score += 3 }
        if appType == "claude" || appType == "claude-desktop" { score += 2 }
        return score
    }
}
