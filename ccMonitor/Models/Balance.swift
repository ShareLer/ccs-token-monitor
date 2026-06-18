import Foundation

enum BalanceRuleKind: String, Codable, CaseIterable, Identifiable {
    case deepseek
    case python

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek 内置"
        case .python: return "Python 脚本"
        }
    }
}

struct BalanceRule: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kind: BalanceRuleKind
    var apiKey: String
    var currency: String
    var script: String

    init(id: String = UUID().uuidString,
         name: String,
         kind: BalanceRuleKind,
         apiKey: String = "",
         currency: String = "CNY",
         script: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.apiKey = apiKey
        self.currency = currency
        self.script = script
    }

    static let deepseekBuiltinID = "builtin.deepseek"

    static func deepseekBuiltin(apiKey: String = "", currency: String = "CNY") -> BalanceRule {
        BalanceRule(id: deepseekBuiltinID,
                    name: "DeepSeek 余额",
                    kind: .deepseek,
                    apiKey: apiKey,
                    currency: currency,
                    script: "")
    }
}

struct ModelBalance: Equatable {
    enum State: Equatable {
        case idle
        case loading
        case value(Double, currency: String)
        case failed(String)
    }

    var state: State = .idle
    var updatedAt: Date?
}

enum BalanceExecutionError: LocalizedError, Equatable {
    case missingAPIKey
    case missingScript
    case invalidAmount(String)
    case network(String)
    case api(String)
    case script(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "缺少 API Key"
        case .missingScript:
            return "缺少 Python 脚本"
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
