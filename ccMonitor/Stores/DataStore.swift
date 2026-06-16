import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    @Published var modelUsages: [ModelUsage] = []
    @Published var summary: SummaryStats = .empty
    @Published var todaySummary: SummaryStats = .empty
    @Published var trend: [TrendPoint] = []
    @Published var heatmap: [HeatmapDay] = []
    @Published var loadError: String?
    @Published var isLoading = false
    /// 下次自动刷新的时刻，供倒计时显示。每次刷新完成后重置。
    @Published var nextRefreshAt: Date?

    @Published var selectedRange: TimeRange = .today {
        didSet { Task { await refreshSelectedRange() } }
    }

    let settings: SettingsStore
    let pricing: PricingStore
    private var timer: Timer?

    init(settings: SettingsStore, pricing: PricingStore) {
        self.settings = settings
        self.pricing = pricing
    }

    private var repo: UsageRepository { UsageRepository(dbPath: settings.dbPath) }

    /// 全量刷新（模型列表 + 汇总 + 趋势 + 热力图）。
    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        let repo = self.repo
        let range = self.selectedRange
        let now = Date()
        let cal = Calendar.current

        do {
            let (usages, summary, todaySummary, trend, heat) = try await Task.detached(priority: .userInitiated) {
                let selectedWindow = DateWindows.resolve(range, now: now, calendar: cal)
                let todayWindow = DateWindows.today(now: now, calendar: cal)
                let trendWindow = DateWindows.lastDays(30, now: now, calendar: cal)
                let heatWindow = DateWindows.thisYear(now: now, calendar: cal)
                return (
                    try repo.fetchModelUsages(window: selectedWindow),
                    try repo.fetchSummary(window: selectedWindow),
                    try repo.fetchSummary(window: todayWindow),
                    try repo.fetchTrend(window: trendWindow),
                    try repo.fetchHeatmap(window: heatWindow)
                )
            }.value
            self.modelUsages = usages
            self.summary = summary
            self.todaySummary = todaySummary
            self.trend = trend
            self.heatmap = heat
            self.loadError = nil
        } catch {
            self.loadError = describe(error)
        }
        // 无论成功失败，刷新完成即重启定时器，使倒计时与下次自动刷新对齐
        // （手动刷新和自动刷新都经此处；仅在定时器已启动时才重启，避免初始 task 提前启动）
        if timer != nil {
            startTimer()
        }
    }

    /// 刷新跟随顶部时间范围的区块（模型明细 + 汇总）。
    func refreshSelectedRange() async {
        let repo = self.repo
        let range = self.selectedRange
        let now = Date()
        let cal = Calendar.current
        do {
            let (usages, summary) = try await Task.detached(priority: .userInitiated) {
                let window = DateWindows.resolve(range, now: now, calendar: cal)
                return (
                    try repo.fetchModelUsages(window: window),
                    try repo.fetchSummary(window: window)
                )
            }.value
            self.modelUsages = usages
            self.summary = summary
            if range == .today {
                self.todaySummary = summary
            }
            self.loadError = nil
        } catch {
            self.loadError = describe(error)
        }
    }

    func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(settings.refreshIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
        scheduleNext()
    }

    func stopTimer() { timer?.invalidate(); timer = nil; nextRefreshAt = nil }

    /// 重置倒计时目标为 now + 刷新间隔。
    private func scheduleNext() {
        nextRefreshAt = Date().addingTimeInterval(TimeInterval(settings.refreshIntervalMinutes * 60))
    }

    private func describe(_ error: Error) -> String {
        if case SQLiteError.openFailed = error {
            return "未找到数据库或无法打开，请在设置中检查路径"
        }
        return "读取失败：\(error.localizedDescription)"
    }
}
