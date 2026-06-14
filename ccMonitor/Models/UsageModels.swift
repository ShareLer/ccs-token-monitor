import Foundation

/// ① 模型列表一行。本月口径 + 今日总量。
struct ModelUsage: Identifiable, Equatable {
    var id: String { model }
    let model: String
    let monthInput: Int
    let monthOutput: Int
    let monthCacheRead: Int
    let monthCacheCreate: Int
    let todayTotal: Int

    var monthTotal: Int { monthInput + monthOutput + monthCacheRead + monthCacheCreate }

    /// 缓存率 = cache_read / (input + cache_read)，本月口径。分母 0 → 0。
    var cacheRate: Double {
        let denom = monthInput + monthCacheRead
        return denom == 0 ? 0 : Double(monthCacheRead) / Double(denom)
    }

    /// 用用户单价重算成本（$/1M token），不读 db 成本字段。
    func cost(with p: ModelPricing) -> Double {
        (Double(monthInput) * p.input
         + Double(monthOutput) * p.output
         + Double(monthCacheRead) * p.cacheRead
         + Double(monthCacheCreate) * p.cacheCreate) / 1_000_000
    }
}

/// ② 汇总区，跟随时间范围，不分模型。
struct SummaryStats: Equatable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreate: Int

    var total: Int { input + output + cacheRead + cacheCreate }
    var cacheRate: Double {
        let denom = input + cacheRead
        return denom == 0 ? 0 : Double(cacheRead) / Double(denom)
    }

    static let empty = SummaryStats(input: 0, output: 0, cacheRead: 0, cacheCreate: 0)
}

/// ③ 折线图一个点。
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
