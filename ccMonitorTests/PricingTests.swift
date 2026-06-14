import XCTest
@testable import ccMonitor

final class PricingTests: XCTestCase {
    func test_modelUsage_monthTotal() {
        let u = ModelUsage(model: "m", monthInput: 100, monthOutput: 200,
                           monthCacheRead: 300, monthCacheCreate: 400, todayTotal: 50)
        XCTAssertEqual(u.monthTotal, 1000)
    }

    func test_cacheRate_formula() {
        // cache_read / (input + cache_read) = 300 / (100 + 300) = 0.75
        let u = ModelUsage(model: "m", monthInput: 100, monthOutput: 0,
                           monthCacheRead: 300, monthCacheCreate: 0, todayTotal: 0)
        XCTAssertEqual(u.cacheRate, 0.75, accuracy: 0.0001)
    }

    func test_cacheRate_zeroDenominator() {
        let u = ModelUsage(model: "m", monthInput: 0, monthOutput: 0,
                           monthCacheRead: 0, monthCacheCreate: 0, todayTotal: 0)
        XCTAssertEqual(u.cacheRate, 0)
    }

    func test_cost_recompute_perMillion() {
        // 单价 $/1M: in=3, out=15, cr=0.3, cc=3.75
        // cost = (1e6*3 + 1e6*15 + 1e6*0.3 + 1e6*3.75)/1e6 = 22.05
        let u = ModelUsage(model: "m", monthInput: 1_000_000, monthOutput: 1_000_000,
                           monthCacheRead: 1_000_000, monthCacheCreate: 1_000_000, todayTotal: 0)
        let p = ModelPricing(input: 3, output: 15, cacheRead: 0.3, cacheCreate: 3.75)
        XCTAssertEqual(u.cost(with: p), 22.05, accuracy: 0.0001)
    }

    func test_cost_defaultPricingIsZero() {
        let u = ModelUsage(model: "m", monthInput: 1_000_000, monthOutput: 1_000_000,
                           monthCacheRead: 0, monthCacheCreate: 0, todayTotal: 0)
        XCTAssertEqual(u.cost(with: ModelPricing()), 0)
    }

    func test_summaryStats_cacheRate() {
        let s = SummaryStats(input: 100, output: 50, cacheRead: 300, cacheCreate: 0)
        XCTAssertEqual(s.total, 450)
        XCTAssertEqual(s.cacheRate, 0.75, accuracy: 0.0001)
    }

    func test_pricing_codable_roundtrip() throws {
        let p = ModelPricing(input: 3, output: 15, cacheRead: 0.3, cacheCreate: 3.75)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(ModelPricing.self, from: data)
        XCTAssertEqual(back, p)
    }

    /// 回归：用真实库里的 deepseek-v4-pro 本月用量 + 用户实际填的单价，成本必须非零。
    /// 坐实「数据/计算层没问题」——此前的 $0.00 是视图层 diff 跳过重绘所致，非计算错误。
    func test_cost_realWorld_deepseekPro_isNonZero() {
        let u = ModelUsage(model: "deepseek-v4-pro",
                           monthInput: 1_000_770, monthOutput: 458_430,
                           monthCacheRead: 91_211_392, monthCacheCreate: 0, todayTotal: 0)
        let p = ModelPricing(input: 3, output: 6, cacheRead: 0.025, cacheCreate: 3)
        // in: 1000770*3/1e6=3.002, out: 458430*6/1e6=2.751, cr: 91211392*0.025/1e6=2.280 → 8.033
        XCTAssertEqual(u.cost(with: p), 8.033, accuracy: 0.01)
        XCTAssertGreaterThan(u.cost(with: p), 0)
    }

    // MARK: topFive 筛选（月Top3 + 日Top2，去重递补到5个）

    /// 构造一个 ModelUsage：月总量靠 monthInput 控制，日总量靠 todayTotal。
    private func mu(_ name: String, month: Int, today: Int) -> ModelUsage {
        ModelUsage(model: name, monthInput: month, monthOutput: 0,
                   monthCacheRead: 0, monthCacheCreate: 0, todayTotal: today)
    }

    func test_topFive_monthTop3_plus_dayTop2_noOverlap() {
        // 月降序: A,B,C,D,E,F  日降序: F,E,...
        let all = [
            mu("A", month: 600, today: 1),
            mu("B", month: 500, today: 2),
            mu("C", month: 400, today: 3),
            mu("D", month: 300, today: 10),  // 不在月Top3
            mu("E", month: 200, today: 50),  // 日第2高
            mu("F", month: 100, today: 90),  // 日第1高
        ]
        let top = ModelUsage.topFive(from: all)
        // 月Top3: A,B,C；日Top2: F,E → 共5个，无重叠
        XCTAssertEqual(top.map(\.model), ["A", "B", "C", "F", "E"])
    }

    func test_topFive_overlap_backfillsFromMonth() {
        // 日Top2 与月Top3 重叠时，从月用量递补
        let all = [
            mu("A", month: 600, today: 100), // 月1 且 日1（重叠）
            mu("B", month: 500, today: 90),  // 月2 且 日2（重叠）
            mu("C", month: 400, today: 1),
            mu("D", month: 300, today: 2),
            mu("E", month: 200, today: 3),
        ]
        let top = ModelUsage.topFive(from: all)
        // 月Top3: A,B,C；日Top2: A,B 全重叠 → 从月递补 D,E → A,B,C,D,E
        XCTAssertEqual(top.map(\.model), ["A", "B", "C", "D", "E"])
    }

    func test_topFive_fewerThanFive_returnsAll() {
        let all = [mu("A", month: 3, today: 1), mu("B", month: 2, today: 1)]
        let top = ModelUsage.topFive(from: all)
        XCTAssertEqual(Set(top.map(\.model)), ["A", "B"])
        XCTAssertEqual(top.count, 2)
    }

    func test_topFive_exactlyFive_allKept() {
        let all = (1...5).map { mu("M\($0)", month: 100 - $0, today: $0) }
        XCTAssertEqual(ModelUsage.topFive(from: all).count, 5)
    }

    func test_topFive_alwaysCapsAtFive() {
        let all = (1...10).map { mu("M\($0)", month: 100 - $0, today: $0 * 2) }
        XCTAssertEqual(ModelUsage.topFive(from: all).count, 5)
    }
}
