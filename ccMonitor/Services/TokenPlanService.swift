import Foundation

enum TokenPlanService {
    private static let timeout: TimeInterval = 15
    private static let log = AppLog("TokenPlanService")

    static func fetch(config: TokenPlanConfig) async throws -> TokenPlanQuota {
        let baseUrl = config.trimmedBaseUrl
        let apiKey = config.trimmedAPIKey
        guard !baseUrl.isEmpty else { throw TokenPlanError.missingBaseURL }
        guard let provider = TokenPlanProvider.detect(baseUrl: baseUrl) else {
            throw TokenPlanError.unknownProvider
        }
        guard config.id.supports(provider) else {
            throw TokenPlanError.unknownProvider
        }
        if provider != .codex {
            guard !apiKey.isEmpty else { throw TokenPlanError.missingAPIKey }
        }

        switch provider {
        case .codex:
            log.info("fetch Codex quota")
            return try await queryCodex(baseUrl: baseUrl)
        case .kimi:
            log.info("fetch Kimi quota")
            return try await queryKimi(apiKey: apiKey)
        case .zhipuCn, .zhipuEn:
            log.info("fetch Zhipu quota provider=\(provider.rawValue)")
            return try await queryZhipu(baseUrl: baseUrl, apiKey: apiKey, provider: provider)
        case .minimaxCn:
            log.info("fetch MiniMax CN quota")
            return try await queryMiniMax(apiKey: apiKey, isCN: true)
        case .minimaxEn:
            log.info("fetch MiniMax EN quota")
            return try await queryMiniMax(apiKey: apiKey, isCN: false)
        }
    }

    static func parseCodexQuota(_ body: [String: Any],
                                queriedAt: Date = Date()) throws -> TokenPlanQuota {
        guard let rateLimit = dict(body["rate_limit"]),
              let primary = dict(rateLimit["primary_window"]),
              let primaryUsed = numeric(primary["used_percent"]) else {
            throw TokenPlanError.parse("Codex usage 响应缺少主额度窗口")
        }
        var tiers: [TokenPlanTier] = []
        tiers.append(TokenPlanTier(kind: .fiveHour,
                                   utilization: primaryUsed,
                                   resetsAt: codexResetDate(primary, queriedAt: queriedAt),
                                   usedValueUSD: nil,
                                   maxValueUSD: nil))
        if let secondary = dict(rateLimit["secondary_window"]) {
            guard let secondaryUsed = numeric(secondary["used_percent"]) else {
                throw TokenPlanError.parse("Codex usage 响应中的次额度窗口无效")
            }
            tiers.append(TokenPlanTier(kind: .weekly,
                                       utilization: secondaryUsed,
                                       resetsAt: codexResetDate(secondary, queriedAt: queriedAt),
                                       usedValueUSD: nil,
                                       maxValueUSD: nil))
        }
        return TokenPlanQuota(provider: .codex,
                              planLabel: string(body["plan_type"]),
                              tiers: tiers,
                              queriedAt: queriedAt)
    }

    static func parseKimiQuota(_ body: [String: Any],
                               provider: TokenPlanProvider = .kimi,
                               queriedAt: Date = Date()) -> TokenPlanQuota {
        var tiers: [TokenPlanTier] = []

        for item in arrayOfDicts(body["limits"]) {
            guard let detail = dict(item["detail"]) else { continue }
            let limit = numeric(detail["limit"]) ?? 0
            let remaining = numeric(detail["remaining"]) ?? 0
            let utilization = utilization(limit: limit, remaining: remaining)
            tiers.append(TokenPlanTier(kind: .fiveHour,
                                       utilization: utilization,
                                       resetsAt: resetDate(detail["resetTime"]),
                                       usedValueUSD: nil,
                                       maxValueUSD: nil))
            break
        }

        if let usage = dict(body["usage"]) {
            let limit = numeric(usage["limit"]) ?? 0
            let remaining = numeric(usage["remaining"]) ?? 0
            tiers.append(TokenPlanTier(kind: .weekly,
                                       utilization: utilization(limit: limit, remaining: remaining),
                                       resetsAt: resetDate(usage["resetTime"]),
                                       usedValueUSD: nil,
                                       maxValueUSD: nil))
        }

        return TokenPlanQuota(provider: provider, planLabel: nil, tiers: tiers, queriedAt: queriedAt)
    }

    static func parseZhipuQuota(_ body: [String: Any],
                                provider: TokenPlanProvider,
                                queriedAt: Date = Date()) throws -> TokenPlanQuota {
        guard let data = dict(body["data"]) else {
            throw TokenPlanError.parse("响应缺少 data 字段")
        }
        return TokenPlanQuota(provider: provider,
                              planLabel: string(data["level"]),
                              tiers: parseZhipuTokenTiers(data),
                              queriedAt: queriedAt)
    }

    static func parseZhipuTokenTiers(_ data: [String: Any]) -> [TokenPlanTier] {
        var fiveHour: ZhipuEntry?
        var weekly: ZhipuEntry?
        var unclassified: [ZhipuEntry] = []

        for item in arrayOfDicts(data["limits"]) {
            guard string(item["type"])?.caseInsensitiveCompare("TOKENS_LIMIT") == .orderedSame else {
                continue
            }
            let resetMs = int64(item["nextResetTime"])
            let entry = ZhipuEntry(resetMs: resetMs,
                                   utilization: numeric(item["percentage"]) ?? 0,
                                   resetsAt: resetMs.flatMap(dateFromTimestamp))
            switch zhipuWindow(item) {
            case .fiveHour where fiveHour == nil:
                fiveHour = entry
            case .weekly where weekly == nil:
                weekly = entry
            default:
                unclassified.append(entry)
            }
        }

        unclassified.sort { left, right in
            if (left.resetMs == nil) != (right.resetMs == nil) {
                return left.resetMs == nil
            }
            return (left.resetMs ?? Int64.min) < (right.resetMs ?? Int64.min)
        }
        for entry in unclassified {
            if fiveHour == nil {
                fiveHour = entry
            } else if weekly == nil {
                weekly = entry
            }
        }

        var tiers: [TokenPlanTier] = []
        if let fiveHour {
            tiers.append(TokenPlanTier(kind: .fiveHour,
                                       utilization: fiveHour.utilization,
                                       resetsAt: fiveHour.resetsAt,
                                       usedValueUSD: nil,
                                       maxValueUSD: nil))
        }
        if let weekly {
            tiers.append(TokenPlanTier(kind: .weekly,
                                       utilization: weekly.utilization,
                                       resetsAt: weekly.resetsAt,
                                       usedValueUSD: nil,
                                       maxValueUSD: nil))
        }
        return tiers
    }

    static func parseMiniMaxQuota(_ body: [String: Any],
                                  provider: TokenPlanProvider,
                                  queriedAt: Date = Date()) -> TokenPlanQuota {
        TokenPlanQuota(provider: provider,
                       planLabel: nil,
                       tiers: parseMiniMaxTiers(body),
                       queriedAt: queriedAt)
    }

    static func parseMiniMaxTiers(_ body: [String: Any]) -> [TokenPlanTier] {
        let general = arrayOfDicts(body["model_remains"]).first {
            string($0["model_name"]) == "general"
        }
        guard let general else { return [] }

        var tiers: [TokenPlanTier] = []
        if let remainingPercent = numeric(general["current_interval_remaining_percent"]) {
            tiers.append(TokenPlanTier(kind: .fiveHour,
                                       utilization: 100 - remainingPercent,
                                       resetsAt: int64(general["end_time"]).flatMap(dateFromTimestamp),
                                       usedValueUSD: nil,
                                       maxValueUSD: nil))
        }

        if int64(general["current_weekly_status"]) == 1,
           let remainingPercent = numeric(general["current_weekly_remaining_percent"]) {
            tiers.append(TokenPlanTier(kind: .weekly,
                                       utilization: 100 - remainingPercent,
                                       resetsAt: int64(general["weekly_end_time"]).flatMap(dateFromTimestamp),
                                       usedValueUSD: nil,
                                       maxValueUSD: nil))
        }
        return tiers
    }

    private static func queryKimi(apiKey: String) async throws -> TokenPlanQuota {
        var request = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!,
                                 timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = try await send(request)
        return parseKimiQuota(body, provider: .kimi)
    }

    private static func queryCodex(baseUrl: String) async throws -> TokenPlanQuota {
        let credentials = try await CodexOAuthService.validCredentials()
        do {
            return try await requestCodex(baseUrl: baseUrl, credentials: credentials)
        } catch let error as TokenPlanError {
            guard case .authentication = error else { throw error }
            let refreshed = try await CodexOAuthService.validCredentials(forceRefresh: true)
            return try await requestCodex(baseUrl: baseUrl, credentials: refreshed)
        }
    }

    private static func requestCodex(baseUrl: String,
                                     credentials: CodexOAuthCredentials) async throws -> TokenPlanQuota {
        guard let url = URL(string: baseUrl) else {
            throw TokenPlanError.missingBaseURL
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = credentials.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TokenPlanError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TokenPlanError.api("响应格式异常")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw TokenPlanError.authentication("HTTP \(http.statusCode)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TokenPlanError.api("HTTP \(http.statusCode)")
        }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenPlanError.parse("无法解析 Codex usage 响应")
        }
        return try parseCodexQuota(body)
    }

    private static func queryZhipu(baseUrl: String,
                                   apiKey: String,
                                   provider: TokenPlanProvider) async throws -> TokenPlanQuota {
        let url = "\(zhipuQuotaBase(baseUrl: baseUrl))/api/monitor/usage/quota/limit"
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

        let body = try await send(request)
        if bool(body["success"]) == false {
            throw TokenPlanError.api(string(body["msg"]) ?? "Unknown error")
        }
        return try parseZhipuQuota(body, provider: provider)
    }

    private static func queryMiniMax(apiKey: String, isCN: Bool) async throws -> TokenPlanQuota {
        let domain = isCN ? "api.minimaxi.com" : "api.minimax.io"
        let url = "https://\(domain)/v1/api/openplatform/coding_plan/remains"
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = try await send(request)
        if let baseResp = dict(body["base_resp"]),
           let statusCode = int64(baseResp["status_code"]),
           statusCode != 0 {
            throw TokenPlanError.api("code \(statusCode): \(string(baseResp["status_msg"]) ?? "Unknown error")")
        }
        return parseMiniMaxQuota(body, provider: isCN ? .minimaxCn : .minimaxEn)
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.error("request failed: \(error.localizedDescription)")
            throw TokenPlanError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            log.error("request failed: non-http response")
            throw TokenPlanError.api("响应格式异常")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            log.error("request authentication failed status=\(http.statusCode)")
            throw TokenPlanError.authentication("HTTP \(http.statusCode)")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            log.error("request failed status=\(http.statusCode)")
            throw TokenPlanError.api("HTTP \(http.statusCode) \(body)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.error("request failed: json parse error")
            throw TokenPlanError.parse("无法解析响应")
        }
        log.info("request succeeded status=\(http.statusCode)")
        return json
    }

    private enum ZhipuWindow {
        case fiveHour
        case weekly
    }

    private struct ZhipuEntry {
        let resetMs: Int64?
        let utilization: Double
        let resetsAt: Date?
    }

    private static func zhipuWindow(_ item: [String: Any]) -> ZhipuWindow? {
        switch int64(item["unit"]) {
        case 3: return .fiveHour
        case 6: return .weekly
        default: return nil
        }
    }

    private static func zhipuQuotaBase(baseUrl: String) -> String {
        baseUrl.lowercased().contains("bigmodel.cn") ? "https://open.bigmodel.cn" : "https://api.z.ai"
    }

    private static func utilization(limit: Double, remaining: Double) -> Double {
        guard limit > 0 else { return 0 }
        return max(limit - remaining, 0) / limit * 100
    }

    private static func codexResetDate(_ window: [String: Any], queriedAt: Date) -> Date? {
        if let resetAt = int64(window["reset_at"]) {
            return dateFromTimestamp(resetAt)
        }
        guard let resetAfter = int64(window["reset_after_seconds"]), resetAfter >= 0 else {
            return nil
        }
        return queriedAt.addingTimeInterval(TimeInterval(resetAfter))
    }

    private static func dict(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func arrayOfDicts(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return value as? String
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func numeric(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        guard let value, !(value is NSNull) else { return nil }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? String {
            return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func resetDate(_ value: Any?) -> Date? {
        if let value = string(value) {
            return iso8601Date(value)
        }
        return int64(value).flatMap(dateFromTimestamp)
    }

    private static func dateFromTimestamp(_ timestamp: Int64) -> Date? {
        let millis = timestamp < 1_000_000_000_000 ? timestamp * 1000 : timestamp
        return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    private static func iso8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
