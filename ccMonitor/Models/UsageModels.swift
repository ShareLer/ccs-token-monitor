import Foundation

/// ① 模型列表一行。当前选中时间范围口径，input 为未命中缓存输入。
struct ModelUsage: Identifiable, Equatable {
    var id: String { model }
    let model: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreate: Int
    let requestCount: Int
    let total: Int

    init(model: String, input: Int, output: Int, cacheRead: Int, cacheCreate: Int, requestCount: Int = 0, total: Int? = nil) {
        self.model = model
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreate = cacheCreate
        self.requestCount = requestCount
        self.total = total ?? (input + output + cacheRead + cacheCreate)
    }

    /// 缓存率 = cache_read / (未命中 input + cache_create + cache_read)。分母 0 → 0。
    var cacheRate: Double {
        let denom = input + cacheCreate + cacheRead
        return denom == 0 ? 0 : Double(cacheRead) / Double(denom)
    }

    /// 用用户单价重算成本（$/1M token），不读 db 成本字段。
    func cost(with p: ModelPricing) -> Double {
        (Double(input) * p.input
         + Double(output) * p.output
         + Double(cacheRead) * p.cacheRead
         + Double(cacheCreate) * p.cacheCreate) / 1_000_000
    }

    func topNValue(for metric: ModelUsageSortMetric, pricing: ModelPricing) -> Double {
        switch metric {
        case .totalTokens:
            return Double(total)
        case .inputTokens:
            return Double(input + cacheCreate)
        case .outputTokens:
            return Double(output)
        case .cacheTokens:
            return Double(cacheRead)
        case .cacheRate:
            return cacheRate
        case .requestCount:
            return Double(requestCount)
        case .cost:
            return cost(with: pricing)
        }
    }
}

enum ModelUsageSortMetric: String, CaseIterable, Identifiable {
    case totalTokens
    case inputTokens
    case outputTokens
    case cacheTokens
    case cacheRate
    case requestCount
    case cost

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .totalTokens: return "总Token量"
        case .inputTokens: return "输入Token量"
        case .outputTokens: return "输出Token量"
        case .cacheTokens: return "缓存量"
        case .cacheRate: return "缓存率"
        case .requestCount: return "请求数"
        case .cost: return "消费金额"
        }
    }
}

extension Array where Element == ModelUsage {
    func topModels(limit: Int,
                   sortMetric: ModelUsageSortMetric,
                   pricing: (String) -> ModelPricing) -> [ModelUsage] {
        let clampedLimit = Swift.min(Swift.max(limit, 1), 10)
        return sorted { lhs, rhs in
            let lhsValue = lhs.topNValue(for: sortMetric, pricing: pricing(lhs.model))
            let rhsValue = rhs.topNValue(for: sortMetric, pricing: pricing(rhs.model))
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            if lhs.total != rhs.total {
                return lhs.total > rhs.total
            }
            return lhs.model < rhs.model
        }
        .prefix(clampedLimit)
        .map { $0 }
    }
}

/// ② 汇总区，跟随时间范围，不分模型，input 为未命中缓存输入。
struct SummaryStats: Equatable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreate: Int
    let requestCount: Int
    let total: Int

    var cacheRate: Double {
        let denom = input + cacheCreate + cacheRead
        return denom == 0 ? 0 : Double(cacheRead) / Double(denom)
    }

    init(input: Int, output: Int, cacheRead: Int, cacheCreate: Int, requestCount: Int = 0, total: Int? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreate = cacheCreate
        self.requestCount = requestCount
        self.total = total ?? (input + output + cacheRead + cacheCreate)
    }

    static let empty = SummaryStats(input: 0, output: 0, cacheRead: 0, cacheCreate: 0)
}

/// ③ 趋势图一个点。
struct TrendPoint: Identifiable, Equatable {
    var id: String { day + "|" + model }
    let day: String        // yyyy-MM-dd
    let model: String
    let total: Int
}

/// ④ 热力图一格。level 在 View 层按全局 max 动态分档。
struct HeatmapDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let total: Int
}

/// 顶部时间范围按钮。
enum TimeRange: Equatable {
    case today
    case last7d
    case last30d
    case thisMonth
    case thisYear
    case custom(Date, Date)
}
