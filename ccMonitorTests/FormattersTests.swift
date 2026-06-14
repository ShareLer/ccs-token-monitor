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
    func test_formatCost() {
        XCTAssertEqual(formatCost(74.7382), "$74.74")
    }
    func test_formatCost_zero() {
        XCTAssertEqual(formatCost(0), "$0.00")
    }
    func test_formatPercent() {
        XCTAssertEqual(formatPercent(0.2345), "23%")
    }
}
