import XCTest
@testable import ccMonitor

final class FormattersTests: XCTestCase {
    func test_formatTokens_millions() {
        XCTAssertEqual(formatTokens(1_234_567), "1.2M")
    }
    func test_formatTokens_thousands() {
        XCTAssertEqual(formatTokens(12_500), "12.5K")
    }
    func test_formatTokens_small() {
        XCTAssertEqual(formatTokens(842), "842")
    }
    func test_formatTokens_zero() {
        XCTAssertEqual(formatTokens(0), "0")
    }
    func test_formatMenuBarTokens_roundsThousands() {
        XCTAssertEqual(formatMenuBarTokens(123_456), "123k")
        XCTAssertEqual(formatMenuBarTokens(123_500), "124k")
    }
    func test_formatMenuBarTokens_roundsMillions() {
        XCTAssertEqual(formatMenuBarTokens(1_234_567), "1M")
        XCTAssertEqual(formatMenuBarTokens(1_500_000), "2M")
    }
    func test_formatMenuBarTokens_small() {
        XCTAssertEqual(formatMenuBarTokens(842), "842")
    }
    func test_formatCost() {
        XCTAssertEqual(formatCost(74.7382), "¥74.74")
    }
    func test_formatCost_zero() {
        XCTAssertEqual(formatCost(0), "¥0.00")
    }
    func test_formatBalance() {
        XCTAssertEqual(formatBalance(12.3, currency: "CNY"), "¥12.30")
        XCTAssertEqual(formatBalance(4.56, currency: "USD"), "$4.56")
        XCTAssertEqual(formatBalance(7.8, currency: "EUR"), "EUR 7.80")
    }
    func test_formatPercent() {
        XCTAssertEqual(formatPercent(0.2345), "23%")
    }

    // 缓存率保留 1 位小数，避免 99.92% 被四舍五入显示成 100%（误导）
    func test_formatCacheRate_keepsOneDecimal() {
        XCTAssertEqual(formatCacheRate(0.9992), "99.9%")
    }
    func test_formatCacheRate_notRoundedTo100() {
        // 关键回归：99.92% 不能显示成 100%
        XCTAssertNotEqual(formatCacheRate(0.9992), "100%")
        XCTAssertNotEqual(formatCacheRate(0.9992), "100.0%")
    }
    func test_formatCacheRate_real100() {
        // input=0 时确实是 100%
        XCTAssertEqual(formatCacheRate(1.0), "100.0%")
    }
    func test_formatCacheRate_zero() {
        XCTAssertEqual(formatCacheRate(0), "0.0%")
    }
}
