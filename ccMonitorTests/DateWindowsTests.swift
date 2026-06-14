import XCTest
@testable import ccMonitor

final class DateWindowsTests: XCTestCase {
    private func makeCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    private func date(_ y: Int,_ mo: Int,_ d: Int,_ h: Int = 0,_ mi: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        return makeCalendar().date(from: comps)!
    }

    func test_todayWindow_startIsMidnight_endIsNextMidnight() {
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.today(now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 6, 14, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 15, 0, 0).timeIntervalSince1970))
    }

    func test_monthWindow_startIsFirstOfMonth() {
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.thisMonth(now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 6, 1, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 7, 1, 0, 0).timeIntervalSince1970))
    }

    func test_lastNDays_7d_startIs6DaysBeforeTodayMidnight() {
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.lastDays(7, now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 6, 8, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 15, 0, 0).timeIntervalSince1970))
    }

    func test_lastNDays_30d() {
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.lastDays(30, now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 5, 16, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 15, 0, 0).timeIntervalSince1970))
    }

    func test_customWindow_inclusiveEndDay() {
        let w = DateWindows.custom(from: date(2026, 6, 1), to: date(2026, 6, 3),
                                   calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 6, 1, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 4, 0, 0).timeIntervalSince1970))
    }

    func test_resolve_dispatchesByRange() {
        let now = date(2026, 6, 14, 17, 30)
        let cal = makeCalendar()
        XCTAssertEqual(DateWindows.resolve(.today, now: now, calendar: cal).start,
                       DateWindows.today(now: now, calendar: cal).start)
        XCTAssertEqual(DateWindows.resolve(.last7d, now: now, calendar: cal).start,
                       DateWindows.lastDays(7, now: now, calendar: cal).start)
        XCTAssertEqual(DateWindows.resolve(.last30d, now: now, calendar: cal).start,
                       DateWindows.lastDays(30, now: now, calendar: cal).start)
    }

    func test_thisYear_startIsJan1_endIsTomorrow() {
        // 本自然年：1月1日 00:00 ..< 今天次日 00:00（含今天，不含未来）
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.thisYear(now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 1, 1, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 15, 0, 0).timeIntervalSince1970))
    }
}
