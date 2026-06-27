import Foundation

/// 所有聚合查询。每次开只读连接，查完关闭。失败抛错，不崩溃。
struct UsageRepository {
    let dbPath: String
    /// 与 cc-switch 官方保持一致：Codex/Gemini 的 input_tokens 含 cache_read；其它 app_type 已是未命中输入。
    private static var cacheInclusiveInputSQL: String {
        """
        app_type IN ('codex', 'gemini')
        """
    }

    private static var normalizedInputSQL: String {
        """
        CASE
            WHEN \(Self.cacheInclusiveInputSQL) AND input_tokens >= cache_read_tokens
                THEN input_tokens - cache_read_tokens
            ELSE input_tokens
          END
        """
    }

    private static var displayTotalSQL: String {
        """
        COALESCE((\(Self.normalizedInputSQL)), 0)
          + COALESCE(output_tokens, 0)
          + COALESCE(cache_read_tokens, 0)
          + COALESCE(cache_creation_tokens, 0)
        """
    }

    private func withDB<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        let db = try SQLiteDatabase(path: dbPath, readonly: true)
        defer { db.close() }
        return try body(db)
    }

    /// ① 模型列表：给定窗口内按 model 聚合，默认按总用量降序取 Top5；limit 为 nil 时返回全量聚合结果。
    func fetchModelUsages(window: DateWindow, limit: Int? = 5) throws -> [ModelUsage] {
        return try withDB { db in
            var usages: [ModelUsage] = []
            let limitClause = limit == nil ? "" : " LIMIT ?"
            let params = limit.map { [window.start, window.end, $0] } ?? [window.start, window.end]
            try db.query("""
                SELECT model,
                       COALESCE(SUM(\(Self.normalizedInputSQL)),0),
                       COALESCE(SUM(output_tokens),0),
                       COALESCE(SUM(cache_read_tokens),0),
                       COALESCE(SUM(cache_creation_tokens),0),
                       COUNT(*),
                       COALESCE(SUM(\(Self.displayTotalSQL)),0) AS total
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY model
                ORDER BY total DESC, model ASC
                \(limitClause);
            """, ints: params) { row in
                usages.append(ModelUsage(model: row.string(0) ?? "",
                                         input: row.int(1),
                                         output: row.int(2),
                                         cacheRead: row.int(3),
                                         cacheCreate: row.int(4),
                                         requestCount: row.int(5),
                                         total: row.int(6)))
            }
            return usages
        }
    }

    /// ② 汇总：给定窗口的原始四类 token 与归一化展示总量。
    func fetchSummary(window: DateWindow) throws -> SummaryStats {
        try withDB { db in
            var s = SummaryStats.empty
            try db.query("""
                SELECT COALESCE(SUM(\(Self.normalizedInputSQL)),0), COALESCE(SUM(output_tokens),0),
                       COALESCE(SUM(cache_read_tokens),0), COALESCE(SUM(cache_creation_tokens),0),
                       COUNT(*),
                       COALESCE(SUM(\(Self.displayTotalSQL)),0)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?;
            """, ints: [window.start, window.end]) { row in
                s = SummaryStats(input: row.int(0), output: row.int(1),
                                 cacheRead: row.int(2), cacheCreate: row.int(3),
                                 requestCount: row.int(4),
                                 total: row.int(5))
            }
            return s
        }
    }

    /// ③ 趋势：按天 × 模型聚合总 token。
    func fetchTrend(window: DateWindow) throws -> [TrendPoint] {
        try withDB { db in
            var totalsByDayModel: [String: [String: Int]] = [:]
            var modelTotals: [String: Int] = [:]
            try db.query("""
                SELECT date(created_at,'unixepoch','localtime') AS day, model,
                       SUM(\(Self.displayTotalSQL))
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY day, model ORDER BY day;
            """, ints: [window.start, window.end]) { row in
                let day = row.string(0) ?? ""
                let model = row.string(1) ?? ""
                let total = row.int(2)
                guard !day.isEmpty, !model.isEmpty else { return }
                totalsByDayModel[day, default: [:]][model] = total
                modelTotals[model, default: 0] += total
            }

            let days = Self.days(in: window)
            let models = modelTotals.sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }.map(\.key)

            var pts: [TrendPoint] = []
            for day in days {
                for model in models {
                    pts.append(TrendPoint(day: day, model: model, total: totalsByDayModel[day]?[model] ?? 0))
                }
            }
            return pts
        }
    }

    private static func days(in window: DateWindow) -> [String] {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone

        let end = Date(timeIntervalSince1970: TimeInterval(window.end))
        var day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(window.start)))
        var days: [String] = []
        while day < end {
            days.append(formatter.string(from: day))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// ④ 热力图：按天聚合总 token。
    func fetchHeatmap(window: DateWindow) throws -> [HeatmapDay] {
        try withDB { db in
            var days: [HeatmapDay] = []
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.timeZone = TimeZone.current
            try db.query("""
                SELECT date(created_at,'unixepoch','localtime') AS day,
                       SUM(\(Self.displayTotalSQL))
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY day ORDER BY day;
            """, ints: [window.start, window.end]) { row in
                guard let d = fmt.date(from: row.string(0) ?? "") else { return }
                days.append(HeatmapDay(date: d, total: row.int(1)))
            }
            return days
        }
    }

    /// 设置面板用：所有有历史数据的模型名。
    func fetchDistinctModels() throws -> [String] {
        try withDB { db in
            var models: [String] = []
            try db.query("SELECT DISTINCT model FROM proxy_request_logs ORDER BY model;") { row in
                if let m = row.string(0) { models.append(m) }
            }
            return models
        }
    }
}
