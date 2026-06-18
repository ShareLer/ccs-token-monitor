# cc-switch monitor

macOS 菜单栏应用，从 `~/.cc-switch/cc-switch.db` 只读读取 token 用量并可视化。

## 功能

- **按模型展示**当前时间范围内用量最多的 5 个模型、缓存率、成本和可配置余额（成本用你自设的单价重算，不读数据库里的成本）
- 每个模型一个进度条，显示该范围内 token 用量，进度条上叠加黑色加粗文字保证对比度
- **时间范围**（当日 / 7天 / 30天 / 自定义）联动汇总统计和模型用量明细：总 token、输入、输出、缓存率 + 缓存率进度条
- **最近 30 天用量趋势**（按天堆叠柱状图，鼠标悬停查看某天全部模型数值）
- **7×52 Token 活动热力图**（按日总 token 动态分 5 档着色，底部标月份）
- **设置面板**：数据库路径、实时拉取有历史数据的模型列表、每模型 4 类单价（输入/输出/缓存读/缓存写，$/1M token）、余额获取逻辑、刷新间隔（5/10/15/30 分钟）

## 关键说明

- 应用以**只读**方式访问 `cc-switch.db`，绝不写入。
- 单价与设置存于 app 自己的 `UserDefaults`，不写回 cc-switch 数据库。
- 总 token 使用展示口径与 cc-switch 官方保持一致：`app_type IN ('codex', 'gemini')` 时，`input_tokens` 已含缓存读，会先扣除 `cache_read_tokens` 得到未命中输入；其它 app_type 的 `input_tokens` 已是未命中输入。总量统一为 `未命中输入 + output + cache_read + cache_create`。
- 缓存率 = `缓存读 / (未命中输入 + 缓存写 + 缓存读)`。
- 聚合查询读取 `proxy_request_logs` 中指定时间范围内的记录，不按 `data_source` 或供应商分组/过滤，直接按模型展示。
- 余额规则存于 app 自己的 `UserDefaults`。模型名包含 `deepseek` 时默认使用 DeepSeek 内置余额查询，也可在设置里绑定其它规则或选择“不显示”。DeepSeek 内置逻辑固定请求官方 `https://api.deepseek.com/user/balance`，API Key 可手动填写，也会尝试从 cc-switch 的 DeepSeek provider 配置中读取。
- 自定义 Python 余额脚本通过本机 `python3 -c` 执行，可读取环境变量 `CCS_MODEL` / `CCS_BALANCE_API_KEY` / `CCS_BALANCE_CURRENCY`，stdout 返回数字或 JSON（如 `{"amount": 12.3}`）。

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
./release.sh v1.0.0 --notes "Release v1.0.0"
```

脚本会构建 Release、打包 `dist/ccMonitor-v1.0.0-macOS.zip`、生成 sha256、创建并推送 tag，然后上传到 `ShareLer/ccs-token-monitor` 的 GitHub Release。发布前工作树不能有未提交的已跟踪改动；未跟踪文件不会被发布脚本处理。

预检查但不推送 tag / 不创建 GitHub Release：

```bash
./release.sh v1.0.0 --dry-run
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
