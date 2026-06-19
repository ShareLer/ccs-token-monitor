# cc-switch monitor

macOS 菜单栏应用，从 `~/.cc-switch/cc-switch.db` 只读读取 token 用量并可视化。

## 界面预览

<p align="center">
  <img src="docs/images/ccmonitor-ui-light.png" alt="ccMonitor 浅色模式" width="360">
  <img src="docs/images/ccmonitor-ui-dark.png" alt="ccMonitor 深色模式" width="360">
</p>

## 功能

- **菜单栏总 Token**：菜单栏直接显示当前统计口径下的总 Token，点击打开完整面板。
- **总 Token 汇总**：按当日 / 7 天 / 30 天 / 自定义时间范围展示总计、缓存、输入、输出、请求数和缓存率。
- **模型用量明细**：展示当前时间范围内用量 Top 5 模型的 Token 占比、缓存率、消费和余额；点击模型行可展开总计 / 缓存 / 输入 / 输出 / 请求数明细。
- **最近 30 天趋势**：支持柱状图 / 折线图两种展示模式，按天展示各模型用量；折线图会额外展示总量曲线，鼠标悬停可查看某天的模型明细和总量。
- **Token 活动热力图**：展示本年度每日总 Token，可在设置中选择完整适配或横向滚动。
- **价格与余额**：支持为每个模型配置输入 / 输出 / 缓存读 / 缓存写单价，并绑定 DeepSeek 内置余额、自定义 Python 脚本或 JS 查询模板。
- **外观模式**：支持跟随系统、浅色、深色三种模式，可从标题栏快速切换。
- **截图导出**：标题栏一键保存完整统计面板长图，保存目录可在设置中配置。
- **刷新设置**：支持手动刷新、自动刷新倒计时，以及 5 / 10 / 15 / 30 分钟刷新间隔。

## 数据说明

- 应用以**只读**方式访问 `cc-switch.db`，单价、余额规则（DeepSeek / Python / JS）和界面设置存于 app 自己的 `UserDefaults`。
- 总 Token 口径与 cc-switch 保持一致：`app_type IN ('codex', 'gemini')` 时会先从 `input_tokens` 扣除 `cache_read_tokens` 得到未命中输入；总量为 `未命中输入 + output + cache_read + cache_create`。
- 请求数按同一时间范围统计 `proxy_request_logs` 记录数；模型明细中按 `model` 分组统计。
- 缓存率 = `缓存读 / (未命中输入 + 缓存写 + 缓存读)`。
- 聚合查询读取 `proxy_request_logs` 中指定时间范围内的记录，不按 `data_source` 或供应商分组。

## 依赖

- macOS 13.0+（实际开发/运行于 macOS 26）
- Xcode 26（首次需同意 license：`sudo xcodebuild -license accept`）
- [XcodeGen](https://github.com/yonsm/XcodeGen)（用于从 `project.yml` 生成工程）：`brew install xcodegen`

## 构建与运行

```bash
# 1. 生成 Xcode 工程（若改动了文件列表需重跑）
xcodegen generate

# 2. 构建（build.sh 内部会自动先 xcodegen generate）
./build.sh            # Release
./build.sh Debug      # Debug

# 3. 运行
open ./build/Build/Products/Release/ccMonitor.app
```

启动后菜单栏出现图标（柱状图），点击弹出面板。这是 LSUIElement 应用，**不在 Dock 显示**。

## 在 Xcode 中开发 / 预览

```bash
xcodegen generate          # 生成 ccMonitor.xcodeproj
open ccMonitor.xcodeproj   # 用 Xcode 打开
```

1. 选中任意 View 文件（如 `DashboardView.swift`），按 `⌥⌘↩` 打开 Canvas 实时预览（每个 View 都带 `#Preview` + mock 数据）
2. `⌘R` 运行；菜单栏出现图标，点击弹出面板
3. `⌘U` 运行单元测试

## 测试

```bash
xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS'
```

数据层（格式化、缓存率/成本公式、时间窗计算、SQLite 封装、聚合查询）有完整单元测试覆盖；UI 层用 SwiftUI Preview 目视验证。

## 发布

发布到 GitHub Releases 需要先安装并登录 GitHub CLI：

```bash
brew install gh
gh auth login
```

创建发布包并上传到 Releases：

```bash
./release.sh v1.0.1 --notes "Release v1.0.1"
```

脚本会构建 Release、打包 `dist/ccMonitor-<tag>-macOS.zip`、生成 sha256、创建并推送 tag，然后上传到 `ShareLer/ccs-token-monitor` 的 GitHub Release。发布前工作树不能有未提交的已跟踪改动；未跟踪文件不会被发布脚本处理。

预检查但不推送 tag / 不创建 GitHub Release：

```bash
./release.sh v1.0.1 --dry-run
```

当前脚本不做 Developer ID 签名或 Apple notarization，公开分发时 macOS 可能提示用户手动允许打开。

## 项目结构

```
ccMonitor/
├── ccMonitorApp.swift          # @main 入口
├── AppDelegate.swift           # NSStatusItem + NSPopover
├── Models/                     # 数据模型 + 价格类型
├── Data/                       # SQLite 封装 / 时间窗 / 聚合查询
├── Stores/                     # 设置 / 价格 / 状态中枢（含定时刷新）
└── Views/                      # 主面板 + 各区块视图 + 组件
ccMonitorTests/                 # 单元测试
project.yml                     # XcodeGen 工程声明
build.sh                        # 构建脚本
release.sh                      # GitHub Releases 发布脚本
```
