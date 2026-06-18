import Foundation

/// ① 模型列表一行。当前选中时间范围口径，input 为未命中缓存输入。
struct ModelUsage: Identifiable, Equatable {
    var id: String { model }
    let model: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreate: Int
    let total: Int

    init(model: String, input: Int, output: Int, cacheRead: Int, cacheCreate: Int, total: Int? = nil) {
        self.model = model
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreate = cacheCreate
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

}

/// ② 汇总区，跟随时间范围，不分模型，input 为未命中缓存输入。
struct SummaryStats: Equatable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreate: Int
    let total: Int

    var cacheRate: Double {
        let denom = input + cacheCreate + cacheRead
        return denom == 0 ? 0 : Double(cacheRead) / Double(denom)
    }

    init(input: Int, output: Int, cacheRead: Int, cacheCreate: Int, total: Int? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreate = cacheCreate
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
    case custom(Date, Date)
}
