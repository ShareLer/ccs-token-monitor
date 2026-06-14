import Foundation

/// 单价，单位 $/1M token。默认全 0，由用户手动填。
struct ModelPricing: Codable, Equatable {
    var input: Double = 0
    var output: Double = 0
    var cacheRead: Double = 0
    var cacheCreate: Double = 0
}
