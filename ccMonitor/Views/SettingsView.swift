import SwiftUI

/// ⑤ 设置面板：左右分栏。左侧分类导航，右侧对应内容。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var pricing: PricingStore
    @ObservedObject var balance: BalanceStore
    let onSaved: () -> Void

    enum Section: String, CaseIterable, Identifiable {
        case basic = "基础设置"
        case pricing = "模型价格"
        case balance = "余额逻辑"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .basic: return "slider.horizontal.3"
            case .pricing: return "dollarsign.circle"
            case .balance: return "creditcard"
            }
        }
    }

    @State private var section: Section = .basic
    @State private var models: [String] = []
    @State private var loadError: String?
    @State private var editingRule: BalanceRule?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .frame(width: 660, height: 460)
        .preferredColorScheme(settings.appearanceMode.preferredColorScheme(systemIsDark: settings.systemAppearanceIsDark))
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
                    case .balance:
                        balanceSection
                    }
                }
                .padding(UB.Spacing.xxl)
            }
            UBDivider()
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

    private var rowOutline: some View {
        RoundedRectangle(cornerRadius: UB.Radius.control, style: .continuous)
            .stroke(
                UB.Canvas.lineColor(.outline, for: colorScheme),
                lineWidth: UB.Canvas.lineWidth(.hairline, for: colorScheme)
            )
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
            UBDivider(style: .hairline)
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
                sectionHeader("外观")
                Picker("", selection: $settings.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
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

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.xl) {
            balanceRulesSection
            balanceModelMappingSection
        }
    }

    private var balanceRulesSection: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.l) {
            HStack {
                sectionHeader("余额获取逻辑", "DeepSeek 内置；自定义 Python 脚本需从 stdout 返回金额或 JSON")
                Spacer()
                Button {
                    editingRule = BalanceRule(name: "自定义余额", kind: .python, currency: "USD", script: "print(0)")
                } label: {
                    Label("添加", systemImage: "plus")
                }
            }

            ForEach(balance.rules) { rule in
                balanceRuleRow(rule)
            }
        }
        .ubCard()
        .sheet(item: $editingRule) { rule in
            BalanceRuleEditor(rule: rule, onCancel: {
                editingRule = nil
            }, onSave: { updated in
                balance.setRule(updated)
                editingRule = nil
            })
        }
    }

    private func balanceRuleRow(_ rule: BalanceRule) -> some View {
        HStack(spacing: UB.Spacing.m) {
            Image(systemName: rule.kind == .deepseek ? "bolt.horizontal.circle" : "terminal")
                .foregroundColor(UB.Palette.balance)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(UB.Font.body).lineLimit(1)
                Text("\(rule.kind.displayName) · \(rule.currency.isEmpty ? "USD" : rule.currency)")
                    .font(UB.Font.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑") { editingRule = rule }
            if rule.id != BalanceRule.deepseekBuiltinID {
                Button(role: .destructive) {
                    balance.deleteRule(id: rule.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除")
            }
        }
        .padding(.horizontal, UB.Spacing.l)
        .padding(.vertical, UB.Spacing.s)
        .background(UB.Canvas.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.control, style: .continuous))
        .overlay(rowOutline)
    }

    private var balanceModelMappingSection: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.l) {
            sectionHeader("模型绑定", "未手动绑定时，模型名包含 deepseek 的条目自动使用 DeepSeek 内置逻辑")
            if models.isEmpty {
                Text(loadError ?? "无模型数据")
                    .font(UB.Font.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(models, id: \.self) { model in
                    balanceMappingRow(model)
                }
            }
        }
        .ubCard()
    }

    private func balanceMappingRow(_ model: String) -> some View {
        HStack(spacing: UB.Spacing.m) {
            Text(model)
                .font(UB.Font.body)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: balanceRuleSelectionBinding(model)) {
                Text("自动/默认").tag("")
                Text("不显示").tag(BalanceStore.disabledRuleID)
                ForEach(balance.rules) { rule in
                    Text(rule.name).tag(rule.id)
                }
            }
            .labelsHidden()
            .frame(width: 180)
            Button {
                Task { await balance.refresh(model: model, dbPath: settings.dbPath) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("测试/刷新余额")
        }
        .padding(.horizontal, UB.Spacing.l)
        .padding(.vertical, UB.Spacing.s)
        .background(UB.Canvas.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.control, style: .continuous))
        .overlay(rowOutline)
    }

    private func balanceRuleSelectionBinding(_ model: String) -> Binding<String> {
        Binding<String>(
            get: { balance.modelRuleIDs[model] ?? "" },
            set: { balance.assign(ruleID: $0.isEmpty ? nil : $0, to: model) }
        )
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
        .overlay(rowOutline)
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
        presentPanel(panel) { url in
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
        presentPanel(panel) { url in
            settings.screenshotDir = url.path
        }
    }

    /// 以 sheet 形式把 panel 依附在设置窗口上：天然随设置窗口居中、永远在其之上、
    /// 不受菜单栏 app(LSUIElement)非前台导致的层级覆盖影响。
    private func presentPanel(_ panel: NSOpenPanel, onPick: @escaping (URL) -> Void) {
        guard let host = NSApp.keyWindow else {
            // 兜底：无宿主窗口时退回独立模态
            if panel.runModal() == .OK, let url = panel.url { onPick(url) }
            return
        }
        panel.beginSheetModal(for: host) { resp in
            if resp == .OK, let url = panel.url { onPick(url) }
        }
    }
}

private struct BalanceRuleEditor: View {
    @State private var draft: BalanceRule
    let onCancel: () -> Void
    let onSave: (BalanceRule) -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(rule: BalanceRule, onCancel: @escaping () -> Void, onSave: @escaping (BalanceRule) -> Void) {
        self._draft = State(initialValue: rule)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var isBuiltinDeepSeek: Bool {
        draft.id == BalanceRule.deepseekBuiltinID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.xl) {
            Text("余额逻辑")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: UB.Spacing.l) {
                labeledField("名称") {
                    TextField("名称", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("类型") {
                    Picker("", selection: $draft.kind) {
                        ForEach(BalanceRuleKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(isBuiltinDeepSeek)
                }

                labeledField("币种") {
                    TextField("USD / CNY", text: $draft.currency)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField(draft.kind == .deepseek ? "DeepSeek API Key" : "API Key 环境变量") {
                    SecureField("sk-...", text: $draft.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                if draft.kind == .python {
                    VStack(alignment: .leading, spacing: UB.Spacing.s) {
                        Text("Python 脚本")
                            .font(UB.Font.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $draft.script)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 150)
                            .overlay(
                                RoundedRectangle(cornerRadius: UB.Radius.control)
                                    .stroke(
                                        UB.Canvas.lineColor(.outline, for: colorScheme),
                                        lineWidth: UB.Canvas.lineWidth(.outline, for: colorScheme)
                                    )
                            )
                        Text("可读取环境变量 CCS_MODEL / CCS_BALANCE_API_KEY / CCS_BALANCE_CURRENCY；stdout 返回数字或 {\"amount\": 12.3}。")
                            .font(UB.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("保存") { onSave(normalized(draft)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: UB.Spacing.s) {
            Text(label)
                .font(UB.Font.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func normalized(_ rule: BalanceRule) -> BalanceRule {
        var rule = rule
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.currency = rule.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if rule.currency.isEmpty {
            rule.currency = rule.kind == .deepseek ? "CNY" : "USD"
        }
        if rule.kind == .deepseek {
            rule.script = ""
        }
        return rule
    }
}

#Preview {
    SettingsView(settings: SettingsStore(), pricing: PricingStore(), balance: BalanceStore(), onSaved: {})
}
