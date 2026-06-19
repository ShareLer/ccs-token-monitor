import Foundation

enum TokenPlanProvider: String, Codable, Equatable, Sendable {
    case kimi
    case zhipuCn
    case zhipuEn
    case minimaxCn
    case minimaxEn

    var displayName: String {
        switch self {
        case .kimi: return "Kimi For Coding"
        case .zhipuCn: return "智谱 GLM"
        case .zhipuEn: return "Zhipu GLM"
        case .minimaxCn, .minimaxEn: return "MiniMax"
        }
    }

    static func detect(baseUrl: String) -> TokenPlanProvider? {
        let url = baseUrl.lowercased()
        if url.contains("api.kimi.com/coding") {
            return .kimi
        }
        if url.contains("open.bigmodel.cn") || url.contains("bigmodel.cn") {
            return .zhipuCn
        }
        if url.contains("api.z.ai") {
            return .zhipuEn
        }
        if url.contains("api.minimaxi.com") {
            return .minimaxCn
        }
        if url.contains("api.minimax.io") {
            return .minimaxEn
        }
        return nil
    }
}

enum TokenPlanConfigID: String, Codable, CaseIterable, Identifiable, Sendable {
    case kimi
    case zhipu
    case minimax

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kimi: return "Kimi"
        case .zhipu: return "智谱"
        case .minimax: return "MiniMax"
        }
    }

    var subtitle: String {
        switch self {
        case .kimi: return "Kimi For Coding"
        case .zhipu: return "Zhipu GLM / 智谱"
        case .minimax: return "MiniMax"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .kimi: return "https://api.kimi.com/coding"
        case .zhipu: return "https://open.bigmodel.cn"
        case .minimax: return "https://api.minimaxi.com"
        }
    }

    func supports(_ provider: TokenPlanProvider) -> Bool {
        switch (self, provider) {
        case (.kimi, .kimi):
            return true
        case (.zhipu, .zhipuCn), (.zhipu, .zhipuEn):
            return true
        case (.minimax, .minimaxCn), (.minimax, .minimaxEn):
            return true
        default:
            return false
        }
    }

    static func from(provider: TokenPlanProvider) -> TokenPlanConfigID {
        switch provider {
        case .kimi:
            return .kimi
        case .zhipuCn, .zhipuEn:
            return .zhipu
        case .minimaxCn, .minimaxEn:
            return .minimax
        }
    }
}

struct TokenPlanConfig: Codable, Equatable, Identifiable, Sendable {
    var id: TokenPlanConfigID
    var enabled: Bool
    var baseUrl: String
    var apiKey: String

    init(id: TokenPlanConfigID,
         enabled: Bool = false,
         baseUrl: String = "",
         apiKey: String = "") {
        self.id = id
        self.enabled = enabled
        self.baseUrl = baseUrl
        self.apiKey = apiKey
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case baseUrl
        case apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(TokenPlanConfigID.self, forKey: .id) ?? .kimi
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }

    var trimmedBaseUrl: String {
        id.defaultBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var detectedProvider: TokenPlanProvider? {
        TokenPlanProvider.detect(baseUrl: trimmedBaseUrl)
    }

    var isProviderCompatible: Bool {
        guard let detectedProvider else { return false }
        return id.supports(detectedProvider)
    }

    var isConfigured: Bool {
        enabled && !trimmedAPIKey.isEmpty && isProviderCompatible
    }
}

enum TokenPlanTierKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHour
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveHour: return "5 hour"
        case .weekly: return "1 week"
        }
    }

    static func fromAPIName(_ name: String) -> TokenPlanTierKind? {
        switch name {
        case "five_hour":
            return .fiveHour
        case "weekly_limit", "seven_day":
            return .weekly
        default:
            return nil
        }
    }
}

struct TokenPlanTier: Equatable, Identifiable, Sendable {
    var kind: TokenPlanTierKind
    var utilization: Double
    var resetsAt: Date?
    var usedValueUSD: Double?
    var maxValueUSD: Double?

    var id: TokenPlanTierKind { kind }

    var clampedFraction: Double {
        min(max(utilization, 0), 100) / 100
    }
}

struct TokenPlanQuota: Equatable, Sendable {
    var provider: TokenPlanProvider
    var planLabel: String?
    var tiers: [TokenPlanTier]
    var queriedAt: Date

    func tier(for kind: TokenPlanTierKind) -> TokenPlanTier? {
        tiers.first { $0.kind == kind }
    }
}

enum TokenPlanLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum TokenPlanError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case missingBaseURL
    case unknownProvider
    case authentication(String)
    case network(String)
    case api(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "缺少 API Key"
        case .missingBaseURL:
            return "缺少 Base URL"
        case .unknownProvider:
            return "未识别 Token Plan 供应商"
        case .authentication(let message):
            return "认证失败：\(message)"
        case .network(let message):
            return "网络错误：\(message)"
        case .api(let message):
            return "接口错误：\(message)"
        case .parse(let message):
            return "解析失败：\(message)"
        }
    }
}
