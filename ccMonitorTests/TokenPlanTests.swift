import XCTest
@testable import ccMonitor

final class TokenPlanTests: XCTestCase {
    func test_detectProvider_matchesKnownCodingPlanURLs() {
        XCTAssertEqual(TokenPlanProvider.detect(baseUrl: "https://api.kimi.com/coding/v1"), .kimi)
        XCTAssertEqual(TokenPlanProvider.detect(baseUrl: "https://open.bigmodel.cn/api/paas/v4"), .zhipuCn)
        XCTAssertEqual(TokenPlanProvider.detect(baseUrl: "https://api.z.ai/api/paas/v4"), .zhipuEn)
        XCTAssertEqual(TokenPlanProvider.detect(baseUrl: "https://api.minimaxi.com/v1"), .minimaxCn)
        XCTAssertEqual(TokenPlanProvider.detect(baseUrl: "https://api.minimax.io/v1"), .minimaxEn)
        XCTAssertNil(TokenPlanProvider.detect(baseUrl: "https://quota.zenmux.example"))
    }

    func test_parseKimiQuota_usesLimitAndRemaining() {
        let quota = TokenPlanService.parseKimiQuota([
            "limits": [
                ["detail": ["limit": 1000, "remaining": 250]]
            ],
            "usage": ["limit": 10_000, "remaining": 4_000]
        ])

        XCTAssertEqual(quota.tier(for: .fiveHour)?.utilization ?? -1, 75, accuracy: 0.0001)
        XCTAssertEqual(quota.tier(for: .weekly)?.utilization ?? -1, 60, accuracy: 0.0001)
    }

    func test_parseZhipuTokenTiers_unitOverridesResetOrder() {
        let tiers = TokenPlanService.parseZhipuTokenTiers([
            "limits": [
                ["type": "TOKENS_LIMIT", "unit": 6, "percentage": 42, "nextResetTime": 1_000_003_600_000],
                ["type": "TOKENS_LIMIT", "unit": 3, "percentage": 1, "nextResetTime": 1_000_018_000_000],
            ]
        ])

        XCTAssertEqual(tiers.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(tiers[0].utilization, 1, accuracy: 0.0001)
        XCTAssertEqual(tiers[1].utilization, 42, accuracy: 0.0001)
    }

    func test_parseZhipuTokenTiers_missingResetFillsFiveHourFirst() {
        let tiers = TokenPlanService.parseZhipuTokenTiers([
            "limits": [
                ["type": "TOKENS_LIMIT", "percentage": 25, "nextResetTime": 2_000_000_000_000],
                ["type": "TOKENS_LIMIT", "percentage": 0],
            ]
        ])

        XCTAssertEqual(tiers.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(tiers[0].utilization, 0, accuracy: 0.0001)
        XCTAssertNil(tiers[0].resetsAt)
        XCTAssertEqual(tiers[1].utilization, 25, accuracy: 0.0001)
    }

    func test_parseMiniMaxTiers_flipsRemainingPercentAndSkipsInactiveWeekly() {
        let tiers = TokenPlanService.parseMiniMaxTiers([
            "model_remains": [
                [
                    "model_name": "general",
                    "current_interval_remaining_percent": 98,
                    "current_weekly_remaining_percent": 100,
                    "current_weekly_status": 3,
                ],
                [
                    "model_name": "video",
                    "current_interval_remaining_percent": 20,
                    "current_weekly_remaining_percent": 20,
                    "current_weekly_status": 1,
                ],
            ]
        ])

        XCTAssertEqual(tiers.map(\.kind), [.fiveHour])
        XCTAssertEqual(tiers[0].utilization, 2, accuracy: 0.0001)
    }

    @MainActor
    func test_tokenPlanStoreDisplaysConfiguredPlansOnly() {
        let name = "ccMonitor.tokenPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TokenPlanStore(defaults: defaults)
        store.setConfig(TokenPlanConfig(id: .kimi,
                                        enabled: false,
                                        baseUrl: "https://api.kimi.com/coding",
                                        apiKey: "sk-test"))
        XCTAssertFalse(store.shouldDisplay)

        store.setConfig(TokenPlanConfig(id: .kimi,
                                        enabled: true,
                                        baseUrl: "https://api.kimi.com/coding",
                                        apiKey: ""))
        XCTAssertFalse(store.shouldDisplay)

        store.setConfig(TokenPlanConfig(id: .kimi,
                                        enabled: true,
                                        baseUrl: "https://api.kimi.com/coding",
                                        apiKey: "sk-test"))
        XCTAssertTrue(store.shouldDisplay)
        XCTAssertEqual(store.activeConfigs.map(\.id), [.kimi])
    }

    @MainActor
    func test_tokenPlanStoreIgnoresStoredURLForPresetProviders() {
        let name = "ccMonitor.tokenPlanFixedURLTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TokenPlanStore(defaults: defaults)

        store.setConfig(TokenPlanConfig(id: .zhipu,
                                        enabled: true,
                                        baseUrl: "https://api.kimi.com/coding",
                                        apiKey: "sk-test"))

        XCTAssertTrue(store.shouldDisplay)
        XCTAssertEqual(store.activeConfigs.map(\.id), [.zhipu])
        XCTAssertEqual(store.activeConfigs.first?.trimmedBaseUrl, "https://open.bigmodel.cn")
    }
}
