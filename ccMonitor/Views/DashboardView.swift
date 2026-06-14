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
        HStack {
            Text("Token 使用量监控").font(.system(size: 16, weight: .semibold))
            Spacer()
            Button { Task { await store.refreshAll() } } label: {
                Image(systemName: "arrow.clockwise")
            }.buttonStyle(.plain).help("刷新")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }.buttonStyle(.plain).help("设置")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
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

#Preview {
    let store = DataStore(settings: SettingsStore(), pricing: PricingStore())
    return DashboardView(store: store)
}
