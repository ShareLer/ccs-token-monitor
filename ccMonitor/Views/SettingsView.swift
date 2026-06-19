import SwiftUI

/// ⑤ 设置面板：左右分栏。左侧分类导航，右侧对应内容。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var pricing: PricingStore
    @ObservedObject var balance: BalanceStore
    @ObservedObject var tokenPlan: TokenPlanStore
    let onSaved: () -> Void

    enum Section: String, CaseIterable, Identifiable {
        case basic = "基础设置"
        case pricing = "模型价格"
        case balance = "余额逻辑"
        case tokenPlan = "Token Plan"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .basic: return "slider.horizontal.3"
            case .pricing: return "dollarsign.circle"
            case .balance: return "creditcard"
            case .tokenPlan: return "chart.pie"
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
        .frame(width: 760, height: 500)
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
                    case .tokenPlan:
                        tokenPlanSection
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
            VStack(alignment: .leading, spacing: UB.Spacing.m) {
                sectionHeader("近30日趋势")
                Picker("", selection: $settings.trendChartDisplayMode) {
                    ForEach(TrendChartDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
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

    private var tokenPlanSection: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.xl) {
            sectionHeader("Token Plan 额度", "启用后随首页刷新一起更新；未启用的计划不会显示在首页")
            ForEach(TokenPlanConfigID.allCases) { id in
                tokenPlanConfigRow(id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    private var balanceRulesSection: some View {
        VStack(alignment: .leading, spacing: UB.Spacing.l) {
            HStack {
                sectionHeader("余额获取逻辑", "支持 DeepSeek 内置、JS 查询模板、自定义 Python 脚本")
                Spacer()
                Button {
                    editingRule = BalanceRule(name: "自定义余额",
                                              kind: .javascript,
                                              currency: "CNY",
                                              script: BalanceRule.javascriptDefaultScript)
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
                Task { await balance.refresh(ruleID: updated.id, dbPath: settings.dbPath) }
            })
        }
    }

    private func balanceRuleRow(_ rule: BalanceRule) -> some View {
        HStack(spacing: UB.Spacing.m) {
            Image(systemName: ruleIcon(rule.kind))
                .foregroundColor(UB.Palette.balance)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(UB.Font.body).lineLimit(1)
                Text(rule.kind.displayName)
                    .font(UB.Font.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            balanceRuleStatus(rule)
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

    private func balanceRuleStatus(_ rule: BalanceRule) -> some View {
        let modelBalance = balance.balance(forRuleID: rule.id)
        let text: String
        let color: Color
        let help: String

        switch modelBalance?.state {
        case .value(let value, let currency):
            text = formatBalance(value, currency: currency)
            color = UB.Palette.balance
            help = "余额 \(text)"
        case .failed(let message):
            text = "失败"
            color = .red
            help = message
        case .loading:
            text = "查询中"
            color = .secondary
            help = "正在查询余额"
        case .idle:
            text = "未查询"
            color = .secondary
            help = "尚未查询余额"
        case .none:
            text = "未查询"
            color = .secondary
            help = "尚未查询余额"
        }

        return Label(text, systemImage: "creditcard")
            .font(UB.Font.caption)
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: 86, alignment: .trailing)
            .help(help)
    }

    private func ruleIcon(_ kind: BalanceRuleKind) -> String {
        switch kind {
        case .deepseek: return "bolt.horizontal.circle"
        case .python: return "terminal"
        case .javascript: return "curlybraces"
        }
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

    private func tokenPlanConfigRow(_ id: TokenPlanConfigID) -> some View {
        let config = tokenPlan.config(for: id)
        return VStack(alignment: .leading, spacing: UB.Spacing.l) {
            HStack(alignment: .center, spacing: UB.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.displayName)
                        .font(UB.Font.cardTitle)
                    Text(id.subtitle)
                        .font(UB.Font.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                tokenPlanStatusLabel(id)
                Toggle("启用", isOn: tokenPlanEnabledBinding(id))
                    .toggleStyle(.switch)
            }

            if config.enabled {
                labeledTokenPlanField("API Key") {
                    SecureField("sk-...", text: tokenPlanAPIKeyBinding(id))
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Label(providerText(for: config), systemImage: providerIcon(for: config))
                        .font(UB.Font.caption)
                        .foregroundStyle(providerColor(for: config))
                    Spacer()
                    Button {
                        Task { await tokenPlan.refresh() }
                    } label: {
                        Label("测试/刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(!config.isConfigured || tokenPlan.state(for: id) == .loading)
                }
            }
        }
        .padding(.horizontal, UB.Spacing.l)
        .padding(.vertical, UB.Spacing.m)
        .background(UB.Canvas.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: UB.Radius.control, style: .continuous))
        .overlay(rowOutline)
    }

    private func tokenPlanEnabledBinding(_ id: TokenPlanConfigID) -> Binding<Bool> {
        Binding(
            get: { tokenPlan.config(for: id).enabled },
            set: { enabled in
                var config = tokenPlan.config(for: id)
                config.enabled = enabled
                tokenPlan.setConfig(config)
                if !enabled {
                    Task { await tokenPlan.refresh() }
                }
            }
        )
    }

    private func tokenPlanAPIKeyBinding(_ id: TokenPlanConfigID) -> Binding<String> {
        Binding(
            get: { tokenPlan.config(for: id).apiKey },
            set: { value in
                var config = tokenPlan.config(for: id)
                config.apiKey = value
                tokenPlan.setConfig(config)
            }
        )
    }

    private func providerText(for config: TokenPlanConfig) -> String {
        guard let provider = config.detectedProvider else {
            return "供应商未配置"
        }
        return "使用 \(provider.displayName)"
    }

    private func providerIcon(for config: TokenPlanConfig) -> String {
        config.detectedProvider == nil ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private func providerColor(for config: TokenPlanConfig) -> Color {
        config.detectedProvider == nil ? .orange : .secondary
    }

    private func tokenPlanStatusLabel(_ id: TokenPlanConfigID) -> some View {
        Group {
            switch tokenPlan.state(for: id) {
            case .idle:
                Text("未查询")
                    .foregroundStyle(.secondary)
            case .loading:
                Text("查询中")
                    .foregroundStyle(.secondary)
            case .loaded:
                Text("已更新")
                    .foregroundStyle(UB.Palette.balance)
            case .failed:
                Text("失败")
                    .foregroundStyle(.red)
            }
        }
        .font(UB.Font.caption)
    }

    private func labeledTokenPlanField<Content: View>(_ label: String,
                                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: UB.Spacing.s) {
            Text(label)
                .font(UB.Font.caption)
                .foregroundStyle(.secondary)
            content()
        }
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
    @State private var validationError: String?
    @State private var isValidating = false
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

    private var scriptBinding: Binding<String> {
        Binding(
            get: { draft.script },
            set: {
                draft.script = normalizeCodeText($0)
                validationError = nil
            }
        )
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

                if draft.kind == .deepseek || draft.kind == .javascript {
                    if draft.kind == .javascript {
                        labeledField("Base URL") {
                            TextField("https://api.example.com", text: $draft.baseUrl)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isValidating)
                                .onChange(of: draft.baseUrl) { _ in validationError = nil }
                        }
                    }

                    labeledField(draft.kind == .deepseek ? "DeepSeek API Key" : "API Key") {
                        SecureField("sk-...", text: $draft.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isValidating)
                            .onChange(of: draft.apiKey) { _ in validationError = nil }
                    }
                }

                if draft.kind == .python || draft.kind == .javascript {
                    VStack(alignment: .leading, spacing: UB.Spacing.s) {
                        Text(draft.kind == .python ? "Python 脚本" : "JS 查询模板")
                            .font(UB.Font.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: scriptBinding)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: draft.kind == .python ? 150 : 220)
                            .disabled(isValidating)
                            .onChange(of: draft.script) { _ in validationError = nil }
                            .onAppear(perform: disableTextSubstitutionsInWindow)
                            .overlay(
                                RoundedRectangle(cornerRadius: UB.Radius.control)
                                    .stroke(
                                        UB.Canvas.lineColor(.outline, for: colorScheme),
                                        lineWidth: UB.Canvas.lineWidth(.outline, for: colorScheme)
                                    )
                            )
                        Text(draft.kind == .python
                             ? "脚本按余额逻辑执行一次并分发给绑定模型；stdout 返回数字或 {\"amount\": 12.3}。"
                             : "模板返回 request 和 extractor；支持 {{baseUrl}} 与 {{apiKey}}，由应用发起请求。")
                            .font(UB.Font.caption)
                            .foregroundStyle(.secondary)
                        if let validationError {
                            Text(validationError)
                                .font(UB.Font.caption)
                                .foregroundStyle(.red)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                    .disabled(isValidating)
                Button(isValidating ? "检查中..." : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isValidating || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 720, height: 640)
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: UB.Spacing.s) {
            Text(label)
                .font(UB.Font.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        let rule = normalized(draft)
        guard rule.kind == .python || rule.kind == .javascript else {
            onSave(rule)
            return
        }

        validationError = nil
        isValidating = true
        Task { @MainActor in
            do {
                switch rule.kind {
                case .python:
                    try await BalanceService.validatePythonSyntax(rule.script)
                case .javascript:
                    try BalanceService.validateJavaScriptTemplate(rule.script,
                                                                  baseUrl: rule.baseUrl.isEmpty ? "https://example.com" : rule.baseUrl,
                                                                  apiKey: rule.apiKey.isEmpty ? "test" : rule.apiKey)
                case .deepseek:
                    break
                }
                isValidating = false
                onSave(rule)
            } catch {
                validationError = error.localizedDescription
                isValidating = false
            }
        }
    }

    private func normalized(_ rule: BalanceRule) -> BalanceRule {
        var rule = rule
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.baseUrl = rule.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        rule.currency = "CNY"
        if rule.kind == .deepseek {
            rule.baseUrl = ""
            rule.script = ""
        } else if rule.kind == .python {
            rule.baseUrl = ""
            rule.apiKey = ""
        }
        rule.script = normalizeCodeText(rule.script)
        return rule
    }

    private func normalizeCodeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "＂", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "＇", with: "'")
    }

    private func disableTextSubstitutionsInWindow() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.contentView?.disableTextSubstitutions()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.keyWindow?.contentView?.disableTextSubstitutions()
        }
    }
}

private extension NSView {
    func disableTextSubstitutions() {
        if let textView = self as? NSTextView {
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
        }
        subviews.forEach { $0.disableTextSubstitutions() }
    }
}

#Preview {
    SettingsView(settings: SettingsStore(), pricing: PricingStore(), balance: BalanceStore(), tokenPlan: TokenPlanStore(), onSaved: {})
}
