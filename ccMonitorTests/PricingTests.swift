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
}
