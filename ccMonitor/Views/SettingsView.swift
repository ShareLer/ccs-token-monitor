import SwiftUI

/// ⑤ 设置面板：左右分栏。左侧分类导航，右侧对应内容。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var pricing: PricingStore
    let onSaved: () -> Void

    enum Section: String, CaseIterable, Identifiable {
        case basic = "基础设置"
        case pricing = "模型价格"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .basic: return "slider.horizontal.3"
            case .pricing: return "dollarsign.circle"
            }
        }
    }

    @State private var section: Section = .basic
    @State private var models: [String] = []
    @State private var loadError: String?

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .frame(width: 660, height: 460)
        .onAppear(perform: loadModels)
    }

    // MARK: 左侧导航

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.xs) {
            Text("设置").font(.system(size: 15, weight: .bold))
                .padding(.horizontal, UB.Spacing.l)
                .padding(.top, UB.Spacing.l).padding(.bottom, UB.Spacing.s)
            ForEach(Section.allCases) { s in
                sidebarItem(s)
            }
            Spacer()
        }
        .frame(width: 168)
        .padding(.vertical, UB.Spacing.m)
        .background(UB.Canvas.barBackground)
    }

    private func sidebarItem(_ s: Section) -> some View {
        let active = section == s
        return HStack(spacing: UB.Spacing.m) {
            Image(systemName: s.icon).font(.system(size: 13)).frame(width: 18)
            Text(s.rawValue).font(UB.Font.body)
            Spacer()
        }
        .padding(.horizontal, UB.Spacing.l)
        .padding(.vertical, UB.Spacing.m)
        .foregroundColor(active ? .white : .primary)
        .background(active ? UB.Palette.accent : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.control, style: .continuous))
        .padding(.horizontal, UB.Spacing.s)
        .contentShape(Rectangle())
        .onTapGesture { section = s }
    }

    // MARK: 右侧内容

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: UB.Spacing.xl) {
                    switch section {
                    case .basic:
                        dataSourceSection
                        generalSection
                    case .pricing:
                        pricingSection
                    }
                }
                .padding(UB.Spacing.xxl)
            }
            Divider()
            HStack {
                Spacer()
                Button("完成") { onSaved() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, UB.Spacing.xxl).padding(.vertical, UB.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UB.Canvas.canvasBackground)
    }

    private func sectionHeader(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(UB.Font.caption).foregroundColor(.secondary)
            }
        }
    }

    private var dataSourceSection: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.xl) {
            VStack(alignment: .leading, spacing: UB.Spacing.l) {
                sectionHeader("数据库路径", "cc-switch 的 SQLite 数据库文件")
                HStack {
                    TextField("路径", text: $settings.dbPath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { pickDBFile() }
                }
                if let err = loadError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(UB.Font.caption).foregroundColor(.red)
                } else {
                    Text("已识别 \(models.count) 个有历史数据的模型")
                        .font(UB.Font.caption).foregroundColor(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: UB.Spacing.l) {
                sectionHeader("截图保存目录", "标题栏截图按钮保存的位置")
                HStack {
                    TextField("未设置", text: $settings.screenshotDir)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { pickScreenshotDir() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.xl) {
            VStack(alignment: .leading, spacing: UB.Spacing.m) {
                sectionHeader("刷新间隔")
                Picker("", selection: $settings.refreshIntervalMinutes) {
                    Text("每5分钟").tag(5)
                    Text("每10分钟").tag(10)
                    Text("每15分钟").tag(15)
                    Text("每30分钟").tag(30)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: UB.Spacing.m) {
                sectionHeader("热力图显示")
                Picker("", selection: $settings.heatmapFitMode) {
                    Text("完全显示本年").tag(HeatmapFitMode.fit)
                    Text("固定大小可滑动").tag(HeatmapFitMode.scroll)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.l) {
            sectionHeader("模型价格", "单价 $ / 1M token，用于计算各模型消费")
            if models.isEmpty {
                Text(loadError ?? "无模型数据")
                    .font(UB.Font.caption).foregroundColor(.secondary)
            } else {
                // 表头
                HStack(spacing: UB.Spacing.m) {
                    Text("模型").font(UB.Font.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                     forEachPriceLabel()
                }
                .padding(.horizontal, UB.Spacing.l)
                ForEach(models, id: \.self) { model in
                    pricingRow(model)
                }
            }
        }
        .ubCard()
    }

    private func forEachPriceLabel() -> some View {
        HStack(spacing: UB.Spacing.s) {
            ForEach(["输入", "输出", "缓存读", "缓存写"], id: \.self) { t in
                Text(t).font(UB.Font.caption).foregroundColor(.secondary)
                    .frame(width: 72, alignment: .center)
            }
        }
    }

    private func pricingRow(_ model: String) -> some View {
        // 用 Binding 直接读写 PricingStore，避免闭包捕获局部变量的问题
        let inputBinding = priceBinding(model, \.input)
        let outputBinding = priceBinding(model, \.output)
        let cacheReadBinding = priceBinding(model, \.cacheRead)
        let cacheCreateBinding = priceBinding(model, \.cacheCreate)
        return HStack(spacing: UB.Spacing.m) {
            Text(model).font(UB.Font.body)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: UB.Spacing.s) {
                priceField(inputBinding)
                priceField(outputBinding)
                priceField(cacheReadBinding)
                priceField(cacheCreateBinding)
            }
        }
        .padding(.horizontal, UB.Spacing.l).padding(.vertical, UB.Spacing.s)
        .background(UB.Canvas.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.control, style: .continuous))
    }

    /// 生成某模型某价格字段的双向绑定。
    private func priceBinding(_ model: String,
                              _ kp: WritableKeyPath<ModelPricing, Double>) -> Binding<Double> {
        Binding<Double>(
            get: { pricing.pricing(for: model)[keyPath: kp] },
            set: { newVal in
                var p = pricing.pricing(for: model)
                p[keyPath: kp] = newVal
                pricing.setPricing(p, for: model)
            }
        )
    }

    private func priceField(_ value: Binding<Double>) -> some View {
        TextField("0", value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
    }

    // MARK: 数据

    private func loadModels() {
        do {
            models = try UsageRepository(dbPath: settings.dbPath).fetchDistinctModels()
            loadError = nil
        } catch {
            models = []
            loadError = "无法读取模型列表，请检查数据库路径"
        }
    }

    private func pickDBFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if runPanelInFront(panel) == .OK, let url = panel.url {
            settings.dbPath = url.path
            loadModels()
        }
    }

    private func pickScreenshotDir() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择"
        if runPanelInFront(panel) == .OK, let url = panel.url {
            settings.screenshotDir = url.path
        }
    }

    /// 菜单栏 app（LSUIElement）默认非前台，NSOpenPanel 会被其它窗口盖住。
    /// 先把 app 激活到前台并置顶 panel，确保选择窗口出现在最上层。
    private func runPanelInFront(_ panel: NSOpenPanel) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)
        return panel.runModal()
    }
}

#Preview {
    SettingsView(settings: SettingsStore(), pricing: PricingStore(), onSaved: {})
}
