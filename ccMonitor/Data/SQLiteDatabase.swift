import Foundation
import SQLite3

enum SQLiteError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case execFailed(String)
}

/// 一行查询结果的列访问器。
struct SQLiteRow {
    fileprivate let stmt: OpaquePointer
    func int(_ col: Int32) -> Int { Int(sqlite3_column_int64(stmt, col)) }
    func double(_ col: Int32) -> Double { sqlite3_column_double(stmt, col) }
    func string(_ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }
}

/// SQLite C API 薄封装。只读模式用于读 cc-switch.db。
final class SQLiteDatabase {
    private var db: OpaquePointer?

    init(path: String, readonly: Bool) throws {
        let flags = readonly
            ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX)
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw SQLiteError.openFailed(msg)
        }
        sqlite3_busy_timeout(db, 2000)
    }

    func close() {
        if db != nil { sqlite3_close(db); db = nil }
    }

    /// 执行无返回值 SQL（建表/插入，测试用）。
    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError.execFailed(msg)
        }
    }

    /// 查询并逐行回调。ints 按位置绑定到 ? 占位符。
    func query(_ sql: String, ints: [Int] = [], _ rowHandler: (SQLiteRow) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (idx, v) in ints.enumerated() {
            sqlite3_bind_int64(stmt, Int32(idx + 1), Int64(v))
        }
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW {
            rowHandler(SQLiteRow(stmt: stmt!))
            rc = sqlite3_step(stmt)
        }
        guard rc == SQLITE_DONE else {
            throw SQLiteError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// 查询单个整数标量。
    func queryScalarInt(_ sql: String, ints: [Int] = []) throws -> Int {
        var result = 0
        try query(sql, ints: ints) { row in result = row.int(0) }
        return result
    }
}
