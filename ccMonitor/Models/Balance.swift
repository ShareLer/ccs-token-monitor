import Foundation

enum BalanceRuleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepseek
    case python
    case javascript

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek 内置"
        case .python: return "Python 脚本"
        case .javascript: return "JS 查询模板"
        }
    }
}

struct BalanceRule: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var kind: BalanceRuleKind
    var apiKey: String
    var baseUrl: String
    var currency: String
    var script: String

    init(id: String = UUID().uuidString,
         name: String,
         kind: BalanceRuleKind,
         apiKey: String = "",
         baseUrl: String = "",
         currency: String = "CNY",
         script: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.currency = currency
        self.script = script
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case apiKey
        case baseUrl
        case currency
        case script
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(BalanceRuleKind.self, forKey: .kind)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "CNY"
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(baseUrl, forKey: .baseUrl)
        try container.encode(currency, forKey: .currency)
        try container.encode(script, forKey: .script)
    }

    static let deepseekBuiltinID = "builtin.deepseek"
    static let javascriptDefaultScript = """
    ({
      request: {
        url: "{{baseUrl}}/v1/usage",
        method: "GET",
        headers: { "Authorization": "Bearer {{apiKey}}" }
      },
      extractor: function(response) {
        const remaining = response?.remaining ?? response?.quota?.remaining ?? response?.balance;
        const unit = response?.unit ?? response?.quota?.unit ?? "USD";
        return {
          isValid: response?.is_active ?? response?.isValid ?? true,
          remaining,
          unit
        };
      }
    })
    """

    static func deepseekBuiltin(apiKey: String = "", currency: String = "CNY") -> BalanceRule {
        BalanceRule(id: deepseekBuiltinID,
                    name: "DeepSeek 余额",
                    kind: .deepseek,
                    apiKey: apiKey,
                    currency: currency,
                    script: "")
    }
}

struct ModelBalance: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case loading
        case value(Double, currency: String)
        case failed(String)
    }

    var state: State = .idle
    var updatedAt: Date?
}

enum BalanceExecutionError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case missingBaseURL
    case missingScript
    case invalidAmount(String)
    case network(String)
    case api(String)
    case script(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "缺少 API Key"
        case .missingBaseURL:
            return "缺少 Base URL"
        case .missingScript:
            return "缺少脚本"
        case .invalidAmount(let value):
            return "无法解析金额：\(value)"
        case .network(let message):
            return "网络错误：\(message)"
        case .api(let message):
            return "接口错误：\(message)"
        case .script(let message):
            return "脚本错误：\(message)"
        }
    }
}
