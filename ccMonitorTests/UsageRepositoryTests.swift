import XCTest
@testable import ccMonitor

final class UsageRepositoryTests: XCTestCase {
    struct UsageRow {
        let model: String
        let created: Int
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheCreate: Int
        let appType: String
        let pricingModel: String?
        let dataSource: String

        init(
            model: String,
            created: Int,
            input: Int,
            output: Int,
            cacheRead: Int,
            cacheCreate: Int,
            appType: String = "claude",
            pricingModel: String? = nil,
            dataSource: String = "session_log"
        ) {
            self.model = model
            self.created = created
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheCreate = cacheCreate
            self.appType = appType
            self.pricingModel = pricingModel
            self.dataSource = dataSource
        }
    }

    /// 在临时目录建一个含 proxy_request_logs 表的库，返回路径。
    func makeTempDB(rows: [(model: String, created: Int, i: Int, o: Int, cr: Int, cc: Int)]) throws -> String {
        try makeTempDB(rows: rows.map {
            UsageRow(model: $0.model, created: $0.created, input: $0.i, output: $0.o, cacheRead: $0.cr, cacheCreate: $0.cc)
        })
    }

    func makeTempDB(rows: [UsageRow]) throws -> String {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("ccm_test_\(UUID().uuidString).db")
        let db = try SQLiteDatabase(path: path, readonly: false)
        try db.exec("""
            CREATE TABLE proxy_request_logs (
                request_id TEXT, provider_id TEXT, app_type TEXT, model TEXT,
                request_model TEXT,
                input_tokens INTEGER, output_tokens INTEGER,
                cache_read_tokens INTEGER, cache_creation_tokens INTEGER,
                total_cost_usd TEXT, latency_ms INTEGER, status_code INTEGER,
                created_at INTEGER, data_source TEXT, pricing_model TEXT
            );
        """)
        for r in rows {
            let pricingModel = r.pricingModel.map { "'\($0)'" } ?? "NULL"
            try db.exec("""
                INSERT INTO proxy_request_logs
                (request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
                 cache_read_tokens, cache_creation_tokens, total_cost_usd, latency_ms,
                 status_code, created_at, data_source, pricing_model)
                VALUES ('r','_session','\(r.appType)','\(r.model)', '\(r.model)', \(r.input), \(r.output), \(r.cacheRead), \(r.cacheCreate),
                        '0', 0, 200, \(r.created), '\(r.dataSource)', \(pricingModel));
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

    func test_fetchModelUsages_filtersWindowAndReturnsTopFive_sortedDesc() throws {
        let path = try makeTempDB(rows: [
            ("alpha", 110, 1000, 0, 0, 0),
            ("alpha", 120,  500, 0, 0, 0),
            ("beta",  130,  900, 0, 0, 0),
            ("gamma", 140,  800, 0, 0, 0),
            ("delta", 150,  700, 0, 0, 0),
            ("eps",   160,  600, 0, 0, 0),
            ("zeta",  170,  500, 0, 0, 0),
            ("outsideHigh", 90, 9999, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let repo = UsageRepository(dbPath: path)
        let usages = try repo.fetchModelUsages(window: DateWindow(start: 100, end: 200))

        XCTAssertEqual(usages.count, 5)
        XCTAssertEqual(usages.map(\.model), ["alpha", "beta", "gamma", "delta", "eps"])
        XCTAssertEqual(usages[0].input, 1500)
        XCTAssertEqual(usages[0].total, 1500)
    }

    func test_fetchModelUsages_appliesModelSpecificTotalSemantics() throws {
        let path = try makeTempDB(rows: [
            UsageRow(
                model: "gpt-5.5",
                created: 110,
                input: 100,
                output: 20,
                cacheRead: 80,
                cacheCreate: 0,
                appType: "codex",
                dataSource: "codex_session"
            ),
            UsageRow(model: "deepseek-v4-pro", created: 110, input: 10, output: 5, cacheRead: 7, cacheCreate: 3),
            UsageRow(
                model: "claude-sonnet-4-6",
                created: 110,
                input: 90,
                output: 4,
                cacheRead: 50,
                cacheCreate: 6,
                appType: "claude-desktop",
                pricingModel: "gpt-5.4",
                dataSource: "proxy"
            ),
            UsageRow(
                model: "codex-deepseek",
                created: 110,
                input: 70,
                output: 3,
                cacheRead: 60,
                cacheCreate: 0,
                appType: "codex",
                pricingModel: "deepseek-v4-flash",
                dataSource: "proxy"
            ),
            UsageRow(
                model: "session-gpt",
                created: 110,
                input: 30,
                output: 2,
                cacheRead: 20,
                cacheCreate: 1,
                pricingModel: "gpt-5.4",
                dataSource: "session_log"
            ),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let repo = UsageRepository(dbPath: path)
        let usages = try repo.fetchModelUsages(window: DateWindow(start: 100, end: 200))

        let gpt = try XCTUnwrap(usages.first { $0.model == "gpt-5.5" })
        XCTAssertEqual(gpt.input, 20)
        XCTAssertEqual(gpt.total, 120)
        XCTAssertEqual(gpt.cacheRate, 0.8, accuracy: 0.0001)

        let deepseek = try XCTUnwrap(usages.first { $0.model == "deepseek-v4-pro" })
        XCTAssertEqual(deepseek.input, 10)
        XCTAssertEqual(deepseek.total, 25)

        let proxiedGPT = try XCTUnwrap(usages.first { $0.model == "claude-sonnet-4-6" })
        XCTAssertEqual(proxiedGPT.input, 90)
        XCTAssertEqual(proxiedGPT.total, 150)

        let codexDeepSeek = try XCTUnwrap(usages.first { $0.model == "codex-deepseek" })
        XCTAssertEqual(codexDeepSeek.input, 10)
        XCTAssertEqual(codexDeepSeek.total, 73)

        let sessionGPT = try XCTUnwrap(usages.first { $0.model == "session-gpt" })
        XCTAssertEqual(sessionGPT.input, 30)
        XCTAssertEqual(sessionGPT.total, 53)
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

    func test_fetchSummary_appliesModelSpecificTotalSemantics() throws {
        let path = try makeTempDB(rows: [
            UsageRow(
                model: "gpt-5.5",
                created: 1000,
                input: 100,
                output: 20,
                cacheRead: 80,
                cacheCreate: 0,
                appType: "codex",
                dataSource: "codex_session"
            ),
            UsageRow(model: "deepseek-v4-pro", created: 1000, input: 10, output: 5, cacheRead: 7, cacheCreate: 3),
            UsageRow(
                model: "claude-sonnet-4-6",
                created: 1000,
                input: 90,
                output: 4,
                cacheRead: 50,
                cacheCreate: 6,
                appType: "claude-desktop",
                pricingModel: "gpt-5.4",
                dataSource: "proxy"
            ),
            UsageRow(
                model: "codex-deepseek",
                created: 1000,
                input: 70,
                output: 3,
                cacheRead: 60,
                cacheCreate: 0,
                appType: "codex",
                pricingModel: "deepseek-v4-flash",
                dataSource: "proxy"
            ),
            UsageRow(
                model: "session-gpt",
                created: 1000,
                input: 30,
                output: 2,
                cacheRead: 20,
                cacheCreate: 1,
                pricingModel: "gpt-5.4",
                dataSource: "session_log"
            ),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        let s = try repo.fetchSummary(window: DateWindow(start: 0, end: 2000))
        XCTAssertEqual(s.input, 160)
        XCTAssertEqual(s.output, 34)
        XCTAssertEqual(s.cacheRead, 217)
        XCTAssertEqual(s.cacheCreate, 10)
        XCTAssertEqual(s.total, 421)
        XCTAssertEqual(s.cacheRate, 217.0 / 377.0, accuracy: 0.0001)
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
