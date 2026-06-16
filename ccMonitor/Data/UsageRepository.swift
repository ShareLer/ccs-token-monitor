import Foundation

/// 所有聚合查询。每次开只读连接，查完关闭。失败抛错，不崩溃。
struct UsageRepository {
    let dbPath: String

    private func withDB<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        let db = try SQLiteDatabase(path: dbPath, readonly: true)
        defer { db.close() }
        return try body(db)
    }

    /// ① 模型列表：给定窗口内按 model 聚合，按总用量降序取 Top5。
    func fetchModelUsages(window: DateWindow, limit: Int = 5) throws -> [ModelUsage] {
        return try withDB { db in
            var usages: [ModelUsage] = []
            try db.query("""
                SELECT model,
                       COALESCE(SUM(input_tokens),0),
                       COALESCE(SUM(output_tokens),0),
                       COALESCE(SUM(cache_read_tokens),0),
                       COALESCE(SUM(cache_creation_tokens),0),
                       COALESCE(SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens),0) AS total
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY model
                ORDER BY total DESC, model ASC
                LIMIT ?;
            """, ints: [window.start, window.end, limit]) { row in
                usages.append(ModelUsage(model: row.string(0) ?? "",
                                         input: row.int(1),
                                         output: row.int(2),
                                         cacheRead: row.int(3),
                                         cacheCreate: row.int(4)))
            }
            return usages
        }
    }

    /// ② 汇总：给定窗口的四类 token 总和。
    func fetchSummary(window: DateWindow) throws -> SummaryStats {
        try withDB { db in
            var s = SummaryStats.empty
            try db.query("""
                SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0),
                       COALESCE(SUM(cache_read_tokens),0), COALESCE(SUM(cache_creation_tokens),0)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?;
            """, ints: [window.start, window.end]) { row in
                s = SummaryStats(input: row.int(0), output: row.int(1),
                                 cacheRead: row.int(2), cacheCreate: row.int(3))
            }
            return s
        }
    }

    /// ③ 趋势：按天 × 模型聚合总 token。
    func fetchTrend(window: DateWindow) throws -> [TrendPoint] {
        try withDB { db in
            var pts: [TrendPoint] = []
            try db.query("""
                SELECT date(created_at,'unixepoch','localtime') AS day, model,
                       SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY day, model ORDER BY day;
            """, ints: [window.start, window.end]) { row in
                pts.append(TrendPoint(day: row.string(0) ?? "", model: row.string(1) ?? "", total: row.int(2)))
            }
            return pts
        }
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
                       SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens)
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
