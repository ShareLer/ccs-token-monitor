import SwiftUI

final class DashboardSizing: ObservableObject {
    @Published var contentHeight: CGFloat = 840
}

private struct DashboardContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DashboardHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct DashboardView: View {
    @ObservedObject var store: DataStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var sizing: DashboardSizing
    @State private var showDatePicker = false
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var screenshotAlert: ScreenshotAlert?
    @State private var expandedModelIDs: Set<String> = []
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    private let log = AppLog("Dashboard")

    /// 截图结果提示。
    private enum ScreenshotAlert: Identifiable {
        case needsDir                 // 未设置保存目录
        case saved(String)            // 成功，附文件名
        case failed(String)           // 失败，附原因
        var id: String {
            switch self {
            case .needsDir: return "needsDir"
            case .saved(let s): return "saved-\(s)"
            case .failed(let s): return "failed-\(s)"
            }
        }
    }

    init(store: DataStore, sizing: DashboardSizing = DashboardSizing()) {
        self.store = store
        self.settings = store.settings
        self.sizing = sizing
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(settings.backgroundStyle == .glass ? Color.clear : UB.Canvas.barBackground)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: DashboardHeaderHeightKey.self,
                                               value: proxy.size.height)
                    }
                )
            UBDivider()
            // 内容整体可滚：总Token + 模型用量 + 趋势图 + 热力图。
            ScrollView {
                VStack(spacing: UB.Spacing.xl) {
                    if let err = store.loadError {
                        Text(err).font(UB.Font.body).foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SummaryView(selectedRange: $store.selectedRange,
                                summary: store.summary,
                                onCustomTap: { showDatePicker = true })
                    ModelListView(usages: store.modelUsages,
                                  total: store.summary.total,
                                  expandedModelIDs: $expandedModelIDs,
                                  pricing: store.pricing,
                                  balance: store.balance,
                                  dbPath: settings.dbPath)
                    TokenPlanView(store: store.tokenPlan)
                    TrendChartView(points: store.trend, displayMode: settings.trendChartDisplayMode)
                    HeatmapView(days: store.heatmap, fitMode: settings.heatmapFitMode)
                }
                .padding(UB.Spacing.xxl)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: DashboardContentHeightKey.self,
                                               value: proxy.size.height)
                    }
                )
            }
        }
        .frame(width: 420)
        .environment(\.appBackgroundStyle, settings.backgroundStyle)
        .onPreferenceChange(DashboardHeaderHeightKey.self) { height in
            headerHeight = height
            updateContentHeight()
        }
        .onPreferenceChange(DashboardContentHeightKey.self) { height in
            contentHeight = height
            updateContentHeight()
        }
        .appBackground(settings.backgroundStyle)
        .preferredColorScheme(settings.appearanceMode.preferredColorScheme(systemIsDark: settings.systemAppearanceIsDark))
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .alert(item: $screenshotAlert) { alert in
            switch alert {
            case .needsDir:
                return Alert(title: Text("请先设置保存目录"),
                             message: Text("截图需要指定保存位置，请在设置中选择截图保存目录。"),
                             primaryButton: .default(Text("去设置")) {
                                 NotificationCenter.default.post(name: .openSettings, object: nil)
                             },
                             secondaryButton: .cancel(Text("取消")))
            case .saved(let name):
                return Alert(title: Text("截图已保存"),
                             message: Text(name),
                             dismissButton: .default(Text("好")))
            case .failed(let reason):
                return Alert(title: Text("截图失败"),
                             message: Text(reason),
                             dismissButton: .default(Text("好")))
            }
        }
        .task { await store.refreshAll() }
    }

    private var header: some View {
        HStack(spacing: UB.Spacing.m) {
            Text("CCS Token Monitor").font(UB.Font.popoverTitle)
            Spacer()
            // 倒计时：距下次自动刷新（加载中不显示，让位给转圈）
            if let next = store.nextRefreshAt, !store.isLoading {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(next.timeIntervalSince(context.date).rounded(.up)))
                    Text(countdownText(remaining))
                        .font(UB.Font.countdown)
                        .foregroundStyle(.tertiary)
                }
            }
            RefreshButton(isLoading: store.isLoading) {
                Task { await store.refreshAll() }
            }
            IconButton(systemName: settings.appearanceMode.icon,
                       help: "外观：\(settings.appearanceMode.displayName)") {
                settings.cycleAppearanceMode()
            }
            IconButton(systemName: "camera", help: "截图") { takeScreenshot() }
            IconButton(systemName: "gearshape", help: "设置") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            IconButton(systemName: "power", help: "退出") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, UB.Spacing.xxl).padding(.vertical, UB.Spacing.xl)
    }

    private func countdownText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func updateContentHeight() {
        let dividerHeight: CGFloat = 1
        sizing.contentHeight = headerHeight + dividerHeight + contentHeight
    }

    /// 截图：渲染完整内容长图保存到设置目录。未设目录则提醒。
    private func takeScreenshot() {
        let dir = settings.screenshotDir
        guard !dir.isEmpty else {
            log.warning("screenshot skipped: directory not set")
            screenshotAlert = .needsDir
            return
        }

        let snapshot = SnapshotView(
            modelUsages: store.modelUsages,
            pricing: store.pricing,
            balance: store.balance,
            dbPath: settings.dbPath,
            summary: store.summary,
            selectedRange: store.selectedRange,
            expandedModelIDs: expandedModelIDs,
            tokenPlan: store.tokenPlan,
            trend: store.trend,
            heatmap: store.heatmap,
            heatmapFitMode: settings.heatmapFitMode,
            trendChartDisplayMode: settings.trendChartDisplayMode,
            appearanceMode: settings.appearanceMode,
            systemAppearanceIsDark: settings.systemAppearanceIsDark,
            backgroundStyle: settings.backgroundStyle
        )
        do {
            let url = try Screenshotter.save(snapshot, toDirectory: dir)
            log.info("screenshot saved: \(url.path)")
            screenshotAlert = .saved(url.lastPathComponent)
        } catch {
            log.error("screenshot failed: \(error.localizedDescription)")
            screenshotAlert = .failed(error.localizedDescription)
        }
    }

    private var datePickerSheet: some View {
        VStack(spacing: 16) {
            Text("选择日期范围").font(.system(size: 16, weight: .semibold))
            DatePicker("开始日期", selection: $customStart, displayedComponents: .date)
            DatePicker("结束日期", selection: $customEnd, displayedComponents: .date)
            HStack {
                Button("取消") { showDatePicker = false }
                Spacer()
                Button("确定") {
                    store.selectedRange = .custom(customStart, customEnd)
                    showDatePicker = false
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 300)
    }
}

/// 刷新按钮：加载中用 macOS 原生 ProgressView 替换图标（参考 UsageBoard，比图标自转更地道）。
private struct RefreshButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            Button(action: action) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("刷新")
        }
    }
}

/// 统一的标题栏图标按钮（borderless + secondary，参考 UsageBoard）。
private struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

#Preview {
    let store = DataStore(settings: SettingsStore(), pricing: PricingStore(), balance: BalanceStore(), tokenPlan: TokenPlanStore())
    return DashboardView(store: store)
}
