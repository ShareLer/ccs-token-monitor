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
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    if let err = store.loadError {
                        Text(err).font(.system(size: 12)).foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ModelListView(usages: store.modelUsages, pricing: store.pricing)
                    SummaryView(selectedRange: $store.selectedRange,
                                summary: store.summary,
                                onCustomTap: { showDatePicker = true })
                    TrendChartView(points: store.trend)
                    HeatmapView(days: store.heatmap, fitMode: settings.heatmapFitMode)
                }
                .padding(16)
            }
        }
        .frame(width: 420)
        .frame(maxHeight: 640)
        .background(Color(NSColor.windowBackgroundColor))
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
        HStack(spacing: 10) {
            Text("Token 使用量监控").font(.system(size: 16, weight: .semibold))
            Spacer()
            // 倒计时：距下次自动刷新
            if let next = store.nextRefreshAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(next.timeIntervalSince(context.date).rounded(.up)))
                    Text(countdownText(remaining))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            RefreshButton(isLoading: store.isLoading) {
                Task { await store.refreshAll() }
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }.buttonStyle(.plain).help("设置")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private func countdownText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
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

/// 刷新按钮：刷新中图标持续旋转。
private struct RefreshButton: View {
    let isLoading: Bool
    let action: () -> Void
    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(angle))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .help("刷新")
        .onChange(of: isLoading) { loading in
            if loading {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            } else {
                withAnimation(.linear(duration: 0.2)) { angle = 0 }
            }
        }
    }
}

#Preview {
    let store = DataStore(settings: SettingsStore(), pricing: PricingStore())
    return DashboardView(store: store)
}
