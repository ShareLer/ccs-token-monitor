import XCTest
@testable import ccMonitor

final class PricingTests: XCTestCase {
    func test_modelUsage_total() {
        let u = ModelUsage(model: "m", input: 100, output: 200,
                           cacheRead: 300, cacheCreate: 400)
        XCTAssertEqual(u.total, 1000)
    }

    func test_cacheRate_formula() {
        // cache_read / (input + cache_create + cache_read) = 300 / (100 + 100 + 300) = 0.6
        let u = ModelUsage(model: "m", input: 100, output: 0,
                           cacheRead: 300, cacheCreate: 100)
        XCTAssertEqual(u.cacheRate, 0.6, accuracy: 0.0001)
    }

    func test_cacheRate_zeroDenominator() {
        let u = ModelUsage(model: "m", input: 0, output: 0,
                           cacheRead: 0, cacheCreate: 0)
        XCTAssertEqual(u.cacheRate, 0)
    }

    func test_cost_recompute_perMillion() {
        // 单价 $/1M: in=3, out=15, cr=0.3, cc=3.75
        // cost = (1e6*3 + 1e6*15 + 1e6*0.3 + 1e6*3.75)/1e6 = 22.05
        let u = ModelUsage(model: "m", input: 1_000_000, output: 1_000_000,
                           cacheRead: 1_000_000, cacheCreate: 1_000_000)
        let p = ModelPricing(input: 3, output: 15, cacheRead: 0.3, cacheCreate: 3.75)
        XCTAssertEqual(u.cost(with: p), 22.05, accuracy: 0.0001)
    }

    func test_cost_defaultPricingIsZero() {
        let u = ModelUsage(model: "m", input: 1_000_000, output: 1_000_000,
                           cacheRead: 0, cacheCreate: 0)
        XCTAssertEqual(u.cost(with: ModelPricing()), 0)
    }

    func test_summaryStats_cacheRate() {
        let s = SummaryStats(input: 100, output: 50, cacheRead: 300, cacheCreate: 100)
        XCTAssertEqual(s.total, 550)
        XCTAssertEqual(s.cacheRate, 0.6, accuracy: 0.0001)
    }

    func test_pricing_codable_roundtrip() throws {
        let p = ModelPricing(input: 3, output: 15, cacheRead: 0.3, cacheCreate: 3.75)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(ModelPricing.self, from: data)
        XCTAssertEqual(back, p)
    }

    /// 回归：用真实库里的 deepseek-v4-pro 用量 + 用户实际填的单价，成本必须非零。
    /// 坐实「数据/计算层没问题」——此前的 $0.00 是视图层 diff 跳过重绘所致，非计算错误。
    func test_cost_realWorld_deepseekPro_isNonZero() {
        let u = ModelUsage(model: "deepseek-v4-pro",
                           input: 1_000_770, output: 458_430,
                           cacheRead: 91_211_392, cacheCreate: 0)
        let p = ModelPricing(input: 3, output: 6, cacheRead: 0.025, cacheCreate: 3)
        // in: 1000770*3/1e6=3.002, out: 458430*6/1e6=2.751, cr: 91211392*0.025/1e6=2.280 → 8.033
        XCTAssertEqual(u.cost(with: p), 8.033, accuracy: 0.01)
        XCTAssertGreaterThan(u.cost(with: p), 0)
    }

    // MARK: topFive 筛选（当前范围用量最多的5个）

    /// 构造一个 ModelUsage：总量靠 input 控制。
    private func mu(_ name: String, total: Int) -> ModelUsage {
        ModelUsage(model: name, input: total, output: 0,
                   cacheRead: 0, cacheCreate: 0)
    }

    func test_topFive_ordersByRangeTotal() {
        let all = [
            mu("A", total: 600),
            mu("B", total: 500),
            mu("C", total: 400),
            mu("D", total: 300),
            mu("E", total: 200),
            mu("F", total: 100),
        ]
        let top = ModelUsage.topFive(from: all)
        XCTAssertEqual(top.map(\.model), ["A", "B", "C", "D", "E"])
    }

    func test_topFive_tieBreaksByModelName() {
        let all = [
            mu("B", total: 100),
            mu("A", total: 100),
            mu("C", total: 90),
        ]
        let top = ModelUsage.topFive(from: all)
        XCTAssertEqual(top.map(\.model), ["A", "B", "C"])
    }

    func test_topFive_fewerThanFive_returnsAll() {
        let all = [mu("A", total: 3), mu("B", total: 2)]
        let top = ModelUsage.topFive(from: all)
        XCTAssertEqual(Set(top.map(\.model)), ["A", "B"])
        XCTAssertEqual(top.count, 2)
    }

    func test_topFive_exactlyFive_allKept() {
        let all = (1...5).map { mu("M\($0)", total: 100 - $0) }
        XCTAssertEqual(ModelUsage.topFive(from: all).count, 5)
    }

    func test_topFive_alwaysCapsAtFive() {
        let all = (1...10).map { mu("M\($0)", total: 100 - $0) }
        XCTAssertEqual(ModelUsage.topFive(from: all).count, 5)
    }
}
