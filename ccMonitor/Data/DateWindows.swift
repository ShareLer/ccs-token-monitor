import Foundation

/// 时间窗端点，半开区间 [start, end) 的 Unix 秒。
struct DateWindow: Equatable {
    let start: Int
    let end: Int
}

enum DateWindows {
    private static func unix(_ d: Date) -> Int { Int(d.timeIntervalSince1970) }

    /// 今日 00:00 ..< 次日 00:00
    static func today(now: Date, calendar: Calendar) -> DateWindow {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 本月 1 号 00:00 ..< 下月 1 号 00:00
    static func thisMonth(now: Date, calendar: Calendar) -> DateWindow {
        let comps = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: comps)!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 本自然年：今年 1 月 1 日 00:00 ..< 今天次日 00:00（含今天，不含未来日期）
    static func thisYear(now: Date, calendar: Calendar) -> DateWindow {
        let comps = calendar.dateComponents([.year], from: now)
        let start = calendar.date(from: comps)!
        let todayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 最近 n 天（含今天）：start = (今天 - (n-1)) 的 00:00，end = 次日 00:00
    static func lastDays(_ n: Int, now: Date, calendar: Calendar) -> DateWindow {
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(n - 1), to: todayStart)!
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 自定义 [from, to]，含 to 当天全天：start = from 当天 00:00，end = to 次日 00:00
    static func custom(from: Date, to: Date, calendar: Calendar) -> DateWindow {
        let start = calendar.startOfDay(for: from)
        let toStart = calendar.startOfDay(for: to)
        let end = calendar.date(byAdding: .day, value: 1, to: toStart)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 按 TimeRange 分派（汇总区用）。
    static func resolve(_ range: TimeRange, now: Date, calendar: Calendar) -> DateWindow {
        switch range {
        case .today: return today(now: now, calendar: calendar)
        case .last7d: return lastDays(7, now: now, calendar: calendar)
        case .last30d: return lastDays(30, now: now, calendar: calendar)
        case .thisMonth: return thisMonth(now: now, calendar: calendar)
        case .thisYear: return thisYear(now: now, calendar: calendar)
        case .custom(let f, let t): return custom(from: f, to: t, calendar: calendar)
        }
    }
}
