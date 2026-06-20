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

    func test_modelUsageTopModels_sortsByConfiguredMetricAndLimit() {
        let usages = [
            ModelUsage(model: "cheap-large", input: 1_000, output: 1_000, cacheRead: 0, cacheCreate: 0, requestCount: 1),
            ModelUsage(model: "expensive-small", input: 1, output: 1, cacheRead: 0, cacheCreate: 0, requestCount: 1),
            ModelUsage(model: "many-requests", input: 1, output: 1, cacheRead: 0, cacheCreate: 0, requestCount: 99),
        ]
        let prices = [
            "expensive-small": ModelPricing(input: 1_000_000, output: 1_000_000)
        ]

        let costTop = usages.topModels(limit: 1, sortMetric: .cost) { prices[$0] ?? ModelPricing() }
        let requestTop = usages.topModels(limit: 1, sortMetric: .requestCount) { _ in ModelPricing() }

        XCTAssertEqual(costTop.map(\.model), ["expensive-small"])
        XCTAssertEqual(requestTop.map(\.model), ["many-requests"])
    }

    func test_modelUsageTopNInputMetricIncludesCacheCreate() {
        let usages = [
            ModelUsage(model: "input-only", input: 100, output: 0, cacheRead: 0, cacheCreate: 0),
            ModelUsage(model: "cache-create", input: 1, output: 0, cacheRead: 0, cacheCreate: 120),
        ]

        let top = usages.topModels(limit: 1, sortMetric: .inputTokens) { _ in ModelPricing() }

        XCTAssertEqual(top.map(\.model), ["cache-create"])
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
}
