import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: DataStore
    @ObservedObject var settings: SettingsStore
    @State private var showSettings = false
    @State private var showDatePicker = false
    @State private var customStart = Date()
    @State private var customEnd = Date()

    init(store: DataStore) {
        self.store = store
        self.settings = store.settings
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(UB.Canvas.barBackground)
            Divider()
            ScrollView {
                VStack(spacing: UB.Spacing.xl) {
                    if let err = store.loadError {
                        Text(err).font(UB.Font.body).foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ModelListView(usages: store.modelUsages, pricing: store.pricing)
                    SummaryView(selectedRange: $store.selectedRange,
                                summary: store.summary,
                                onCustomTap: { showDatePicker = true })
                    TrendChartView(points: store.trend)
                    HeatmapView(days: store.heatmap, fitMode: settings.heatmapFitMode)
                }
                .padding(UB.Spacing.xxl)
            }
        }
        .frame(width: 420)
        .frame(maxHeight: 640)
        .background(UB.Canvas.canvasBackground)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: store.settings, pricing: store.pricing,
                         onSaved: { showSettings = false; Task { await store.refreshAll() } })
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .task { await store.refreshAll() }
    }

    private var header: some View {
        HStack(spacing: UB.Spacing.m) {
            Text("Token 使用量监控").font(UB.Font.popoverTitle)
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
            IconButton(systemName: "gearshape", help: "设置") { showSettings = true }
            IconButton(systemName: "power", help: "退出") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, UB.Spacing.xxl).padding(.vertical, UB.Spacing.xl)
    }

    private func countdownText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
    let store = DataStore(settings: SettingsStore(), pricing: PricingStore())
    return DashboardView(store: store)
}
