import Foundation

/// 所有聚合查询。每次开只读连接，查完关闭。失败抛错，不崩溃。
struct UsageRepository {
    let dbPath: String

    private func withDB<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        let db = try SQLiteDatabase(path: dbPath, readonly: true)
        defer { db.close() }
        return try body(db)
    }

    /// ① 模型列表：本月按 model 聚合 + 今日总量合并，按本月用量降序。
    func fetchModelUsages(now: Date, calendar: Calendar) throws -> [ModelUsage] {
        let month = DateWindows.thisMonth(now: now, calendar: calendar)
        let today = DateWindows.today(now: now, calendar: calendar)

        return try withDB { db in
            var monthRows: [(String, Int, Int, Int, Int)] = []
            try db.query("""
                SELECT model, SUM(input_tokens), SUM(output_tokens),
                       SUM(cache_read_tokens), SUM(cache_creation_tokens)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY model;
            """, ints: [month.start, month.end]) { row in
                monthRows.append((row.string(0) ?? "", row.int(1), row.int(2), row.int(3), row.int(4)))
            }

            var todayMap: [String: Int] = [:]
            try db.query("""
                SELECT model,
                       SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY model;
            """, ints: [today.start, today.end]) { row in
                todayMap[row.string(0) ?? ""] = row.int(1)
            }

            let usages = monthRows.map { r in
                ModelUsage(model: r.0, monthInput: r.1, monthOutput: r.2,
                           monthCacheRead: r.3, monthCacheCreate: r.4,
                           todayTotal: todayMap[r.0] ?? 0)
            }
            return usages.sorted { $0.monthTotal > $1.monthTotal }
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
