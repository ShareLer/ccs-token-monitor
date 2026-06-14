import XCTest
@testable import ccMonitor

final class UsageRepositoryTests: XCTestCase {
    /// 在临时目录建一个含 proxy_request_logs 表的库，返回路径。
    func makeTempDB(rows: [(model: String, created: Int, i: Int, o: Int, cr: Int, cc: Int)]) throws -> String {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("ccm_test_\(UUID().uuidString).db")
        let db = try SQLiteDatabase(path: path, readonly: false)
        try db.exec("""
            CREATE TABLE proxy_request_logs (
                request_id TEXT, provider_id TEXT, app_type TEXT, model TEXT,
                input_tokens INTEGER, output_tokens INTEGER,
                cache_read_tokens INTEGER, cache_creation_tokens INTEGER,
                total_cost_usd TEXT, latency_ms INTEGER, status_code INTEGER,
                created_at INTEGER, data_source TEXT
            );
        """)
        for r in rows {
            try db.exec("""
                INSERT INTO proxy_request_logs
                (request_id, provider_id, app_type, model, input_tokens, output_tokens,
                 cache_read_tokens, cache_creation_tokens, total_cost_usd, latency_ms,
                 status_code, created_at, data_source)
                VALUES ('r','_session','claude','\(r.model)', \(r.i), \(r.o), \(r.cr), \(r.cc),
                        '0', 0, 200, \(r.created), 'session_log');
            """)
        }
        db.close()
        return path
    }

    func test_open_readonly_existing() throws {
        let path = try makeTempDB(rows: [("m", 1000, 1, 2, 3, 4)])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path, readonly: true)
        defer { db.close() }
        let count = try db.queryScalarInt("SELECT COUNT(*) FROM proxy_request_logs;")
        XCTAssertEqual(count, 1)
    }

    func test_open_missingFile_throws() {
        XCTAssertThrowsError(try SQLiteDatabase(path: "/nonexistent/xx.db", readonly: true))
    }

    func test_queryRows_withParams() throws {
        let path = try makeTempDB(rows: [
            ("a", 100, 1, 0, 0, 0),
            ("b", 200, 2, 0, 0, 0),
            ("a", 300, 4, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path, readonly: true)
        defer { db.close() }
        var got: [(String, Int)] = []
        try db.query(
            "SELECT model, SUM(input_tokens) FROM proxy_request_logs WHERE created_at >= ? AND created_at < ? GROUP BY model ORDER BY model;",
            ints: [150, 400]
        ) { row in
            got.append((row.string(0) ?? "", row.int(1)))
        }
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got[0].0, "a"); XCTAssertEqual(got[0].1, 4)
        XCTAssertEqual(got[1].0, "b"); XCTAssertEqual(got[1].1, 2)
    }

    func test_fetchModelUsages_mergesMonthAndToday_sortedDesc() throws {
        let cal = Calendar.current
        let now = Date()
        let month = DateWindows.thisMonth(now: now, calendar: cal)
        let today = DateWindows.today(now: now, calendar: cal)
        let monthOnlyTs = month.start + 60
        let todayTs = today.start + 60
        let path = try makeTempDB(rows: [
            ("big",   monthOnlyTs, 1000, 0, 0, 0),
            ("big",   todayTs,      500, 0, 0, 0),
            ("small", monthOnlyTs,  100, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let repo = UsageRepository(dbPath: path)
        let usages = try repo.fetchModelUsages(now: now, calendar: cal)

        XCTAssertEqual(usages.count, 2)
        XCTAssertEqual(usages[0].model, "big")
        XCTAssertEqual(usages[0].monthInput, 1500)
        XCTAssertEqual(usages[0].todayTotal, 500)
        XCTAssertEqual(usages[1].model, "small")
        XCTAssertEqual(usages[1].todayTotal, 0)
    }

    func test_fetchSummary_forWindow() throws {
        let path = try makeTempDB(rows: [
            ("a", 1000, 10, 20, 30, 40),
            ("b", 1000, 1, 2, 3, 4),
            ("c", 9_999_999_999, 999, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        let s = try repo.fetchSummary(window: DateWindow(start: 0, end: 2000))
        XCTAssertEqual(s.input, 11)
        XCTAssertEqual(s.output, 22)
        XCTAssertEqual(s.cacheRead, 33)
        XCTAssertEqual(s.cacheCreate, 44)
    }

    func test_fetchTrend_groupsByDayAndModel() throws {
        let d1 = 1_780_000_000
        let d2 = d1 + 86_400
        let path = try makeTempDB(rows: [
            ("a", d1, 5, 0, 0, 0),
            ("a", d1, 5, 0, 0, 0),
            ("b", d1, 1, 0, 0, 0),
            ("a", d2, 7, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        let pts = try repo.fetchTrend(window: DateWindow(start: d1 - 10, end: d2 + 86_400))
        let aDay1 = pts.first { $0.model == "a" && $0.total == 10 }
        XCTAssertNotNil(aDay1)
        XCTAssertGreaterThanOrEqual(pts.count, 3)
    }

    func test_fetchHeatmap_sumsPerDay() throws {
        let d1 = 1_780_000_000
        let path = try makeTempDB(rows: [
            ("a", d1, 5, 5, 0, 0),
            ("b", d1, 1, 1, 1, 1),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        let days = try repo.fetchHeatmap(window: DateWindow(start: d1 - 10, end: d1 + 86_400))
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].total, 14)
    }

    func test_fetchDistinctModels_sorted() throws {
        let path = try makeTempDB(rows: [
            ("zeta", 1, 1, 0, 0, 0),
            ("alpha", 2, 1, 0, 0, 0),
            ("alpha", 3, 1, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        XCTAssertEqual(try repo.fetchDistinctModels(), ["alpha", "zeta"])
    }

    func test_missingDB_throwsNotCrash() {
        let repo = UsageRepository(dbPath: "/nonexistent/x.db")
        XCTAssertThrowsError(try repo.fetchSummary(window: DateWindow(start: 0, end: 1)))
    }
}
