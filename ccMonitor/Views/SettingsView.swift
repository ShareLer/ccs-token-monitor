import SwiftUI

/// ⑤ 设置面板：db路径 / 模型单价 / 刷新间隔。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var pricing: PricingStore
    let onSaved: () -> Void

    @State private var models: [String] = []
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置").font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 4) {
                Text("数据库路径").font(.system(size: 12, weight: .medium))
                HStack {
                    TextField("路径", text: $settings.dbPath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { pickDBFile() }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("刷新间隔").font(.system(size: 12, weight: .medium))
                Picker("", selection: $settings.refreshIntervalMinutes) {
                    Text("每5分钟").tag(5)
                    Text("每10分钟").tag(10)
                    Text("每15分钟").tag(15)
                    Text("每30分钟").tag(30)
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Text("模型价格（$ / 1M token）").font(.system(size: 12, weight: .medium))
            if let err = loadError {
                Text(err).font(.system(size: 11)).foregroundColor(.red)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(models, id: \.self) { model in
                        pricingRow(model)
                    }
                }
            }
            .frame(maxHeight: 240)

            HStack {
                Spacer()
                Button("完成") { onSaved() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: loadModels)
    }

    private func pricingRow(_ model: String) -> some View {
        // 用 Binding 直接读写 PricingStore，避免闭包捕获局部变量的问题
        let inputBinding = Binding<Double>(
            get: { pricing.pricing(for: model).input },
            set: { newVal in
                var p = pricing.pricing(for: model)
                p.input = newVal
                pricing.setPricing(p, for: model)
            }
        )
        let outputBinding = Binding<Double>(
            get: { pricing.pricing(for: model).output },
            set: { newVal in
                var p = pricing.pricing(for: model)
                p.output = newVal
                pricing.setPricing(p, for: model)
            }
        )
        let cacheReadBinding = Binding<Double>(
            get: { pricing.pricing(for: model).cacheRead },
            set: { newVal in
                var p = pricing.pricing(for: model)
                p.cacheRead = newVal
                pricing.setPricing(p, for: model)
            }
        )
        let cacheCreateBinding = Binding<Double>(
            get: { pricing.pricing(for: model).cacheCreate },
            set: { newVal in
                var p = pricing.pricing(for: model)
                p.cacheCreate = newVal
                pricing.setPricing(p, for: model)
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(model).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                priceField("输入", inputBinding)
                priceField("输出", outputBinding)
                priceField("缓存读", cacheReadBinding)
                priceField("缓存写", cacheCreateBinding)
            }
        }
        .padding(8)
        .background(Color(hex: 0xFAFAFA))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func priceField(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
        }
    }

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
        if panel.runModal() == .OK, let url = panel.url {
            settings.dbPath = url.path
            loadModels()
        }
    }
}

#Preview {
    SettingsView(settings: SettingsStore(), pricing: PricingStore(), onSaved: {})
}
