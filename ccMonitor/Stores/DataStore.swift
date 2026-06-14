import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    @Published var modelUsages: [ModelUsage] = []
    @Published var summary: SummaryStats = .empty
    @Published var trend: [TrendPoint] = []
    @Published var heatmap: [HeatmapDay] = []
    @Published var loadError: String?
    @Published var isLoading = false

    @Published var selectedRange: TimeRange = .today {
        didSet { Task { await refreshSummary() } }
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
            let (usages, summary, trend, heat) = try await Task.detached(priority: .userInitiated) {
                let summaryWindow = DateWindows.resolve(range, now: now, calendar: cal)
                let trendWindow = DateWindows.lastDays(30, now: now, calendar: cal)
                let heatWindow = DateWindows.thisYear(now: now, calendar: cal)
                return (
                    try repo.fetchModelUsages(now: now, calendar: cal),
                    try repo.fetchSummary(window: summaryWindow),
                    try repo.fetchTrend(window: trendWindow),
                    try repo.fetchHeatmap(window: heatWindow)
                )
            }.value
            self.modelUsages = usages
            self.summary = summary
            self.trend = trend
            self.heatmap = heat
            self.loadError = nil
        } catch {
            self.loadError = describe(error)
        }
    }

    /// 仅刷新汇总（时间范围切换时）。
    func refreshSummary() async {
        let repo = self.repo
        let range = self.selectedRange
        let now = Date()
        let cal = Calendar.current
        do {
            let s = try await Task.detached(priority: .userInitiated) {
                try repo.fetchSummary(window: DateWindows.resolve(range, now: now, calendar: cal))
            }.value
            self.summary = s
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
    }

    func stopTimer() { timer?.invalidate(); timer = nil }

    private func describe(_ error: Error) -> String {
        if case SQLiteError.openFailed = error {
            return "未找到数据库或无法打开，请在设置中检查路径"
        }
        return "读取失败：\(error.localizedDescription)"
    }
}
