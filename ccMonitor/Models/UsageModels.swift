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

    /// 模型列表展示筛选：月用量 Top3 + 日用量 Top2，去重；不足 5 个时按月用量降序递补，固定最多 5 个。
    static func topFive(from all: [ModelUsage]) -> [ModelUsage] {
        let byMonth = all.sorted { $0.monthTotal > $1.monthTotal }
        let byToday = all.sorted { $0.todayTotal > $1.todayTotal }

        var result: [ModelUsage] = []
        var picked = Set<String>()
        func add(_ u: ModelUsage) {
            guard !picked.contains(u.model) else { return }
            picked.insert(u.model)
            result.append(u)
        }

        byMonth.prefix(3).forEach(add)              // 月 Top3
        byToday.prefix(2).forEach(add)              // 日 Top2（去重）
        if result.count < 5 {                       // 不足 5 个：按月用量递补
            for u in byMonth where result.count < 5 { add(u) }
        }
        return Array(result.prefix(5))
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
