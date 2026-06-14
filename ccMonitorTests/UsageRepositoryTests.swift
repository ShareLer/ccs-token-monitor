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
}
