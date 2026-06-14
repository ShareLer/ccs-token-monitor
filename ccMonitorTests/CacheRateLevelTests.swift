import XCTest
@testable import ccMonitor

final class CacheRateLevelTests: XCTestCase {
    // 入参是 0...1 的 fraction，阈值按百分比：<80 low，80~95 medium，>=95 high。
    // 边界归属：80→medium（"80以下用红"，故 80 不算红）；95→high（"95以上用绿"，含 95）。

    func test_low_below80() {
        XCTAssertEqual(CacheRateLevel.from(fraction: 0.0), .low)
        XCTAssertEqual(CacheRateLevel.from(fraction: 0.5), .low)
        XCTAssertEqual(CacheRateLevel.from(fraction: 0.799), .low)
    }

    func test_boundary80_isMedium() {
        XCTAssertEqual(CacheRateLevel.from(fraction: 0.80), .medium)
    }

    func test_medium_between80and95() {
        XCTAssertEqual(CacheRateLevel.from(fraction: 0.85), .medium)
        XCTAssertEqual(CacheRateLevel.from(fraction: 0.949), .medium)
    }

    func test_boundary95_isHigh() {
        XCTAssertEqual(CacheRateLevel.from(fraction: 0.95), .high)
    }

    func test_high_above95() {
        XCTAssertEqual(CacheRateLevel.from(fraction: 0.97), .high)
        XCTAssertEqual(CacheRateLevel.from(fraction: 1.0), .high)
    }
}
