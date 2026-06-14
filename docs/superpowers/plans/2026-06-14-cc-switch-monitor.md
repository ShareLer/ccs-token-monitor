# cc-switch monitor 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 macOS 菜单栏应用，从 `~/.cc-switch/cc-switch.db` 只读读取 token 用量，按模型展示用量/成本/缓存率，并提供折线图、热力图与可配置价格。

**Architecture:** 纯原生 SwiftUI + AppKit。`NSStatusItem`（仅图标）点击弹出 `NSPopover` 承载 SwiftUI 面板。数据层用 SQLite C API 只读查询，时间窗端点在 Swift 侧用 `Calendar` 计算。状态由 `DataStore`（ObservableObject）集中管理，定时刷新。价格与设置存 app 自己的 UserDefaults，绝不写 cc-switch.db。

**Tech Stack:** Swift 5.9+ / SwiftUI / AppKit (NSStatusItem, NSPopover) / Swift Charts / SQLite3 (系统自带 libsqlite3) / XCTest / Xcode 26.

**对应 spec:** `docs/superpowers/specs/2026-06-14-cc-switch-monitor-design.md`

---

## 前置约束（务必先读）

- **环境已就绪**：Xcode license 已同意，XcodeGen 已安装（见 Task 0）。项目用 XcodeGen 从 `project.yml` 生成，**每次新增 .swift 文件后需重跑 `xcodegen generate`**。
- **数据层走 TDD**（纯逻辑，用 XCTest + 临时 SQLite 严格测试）；**UI 层用 SwiftUI Preview 目视验证**，不写脆弱 UI 单测。
- **时间窗端点在 Swift 侧用 `Calendar` 计算**为 Unix 秒，SQL 只用 `:start`/`:end` 参数过滤。
- 数据库 `created_at` 是**秒级 Unix 时间戳**；四类 token 字段 `input_tokens/output_tokens/cache_read_tokens/cache_creation_tokens`。
- 价格单位 **$/1M token**，默认全 0。
- 缓存率公式：`cache_read / (input + cache_read)`，分母为 0 时为 0。

---

## 文件结构

```
ccMonitor.xcodeproj
ccMonitor/                       # App target
├── ccMonitorApp.swift           // @main，绑定 AppDelegate
├── AppDelegate.swift            // NSStatusItem + NSPopover 生命周期
├── Models/
│   ├── UsageModels.swift        // ModelUsage / SummaryStats / TrendPoint / HeatmapDay / TimeRange
│   └── Pricing.swift            // ModelPricing(4类单价, Codable)
├── Data/
│   ├── SQLiteDatabase.swift     // SQLite C API 薄封装(只读)
│   ├── DateWindows.swift        // 时间窗端点计算(纯函数)
│   └── UsageRepository.swift    // 聚合查询，返回结构体
├── Stores/
│   ├── SettingsStore.swift      // dbPath / refreshIntervalMinutes (UserDefaults)
│   ├── PricingStore.swift       // [model: ModelPricing] (UserDefaults, Codable)
│   └── DataStore.swift          // ObservableObject 状态中枢 + 定时器
├── Views/
│   ├── DashboardView.swift      // 主面板容器(420px)
│   ├── ModelListView.swift      // ① 模型列表 + 进度条
│   ├── SummaryView.swift        // ② 时间范围 + 汇总
│   ├── TrendChartView.swift     // ③ 折线图
│   ├── HeatmapView.swift        // ④ 热力图
│   ├── SettingsView.swift       // ⑤ 设置面板
│   └── Components/
│       ├── UsageProgressBar.swift
│       ├── TimeRangeSelector.swift
│       └── Formatters.swift     // token/$ 数字格式化(纯函数，可测)
└── Resources/
    ├── Assets.xcassets
    └── Info.plist               // LSUIElement=YES
ccMonitorTests/                  # Unit Test target
├── DateWindowsTests.swift
├── UsageRepositoryTests.swift
├── PricingTests.swift
└── FormattersTests.swift
```

---

## Task 0: 前置环境（已就绪，确认即可）

- [x] **Step 1: Xcode license** — 已同意（`swift --version` 正常输出 Swift 6.3.2）。
- [x] **Step 2: XcodeGen** — 已 `brew install xcodegen`。

确认命令：
Run: `swift --version && xcodegen --version`
Expected: 两者均正常输出版本号。

---

## Task 1: 用 XcodeGen 声明式生成项目骨架

用 `project.yml` 声明项目，`xcodegen` 生成 `.xcodeproj`。优点：纳入 git 可复现、subagent 可全自动 `xcodebuild`。生成的 `.xcodeproj` 照样能在 Xcode 打开预览。

> **前置**：已 `brew install xcodegen`（验证 `xcodegen --version`）。源码目录用占位文件先建好，否则 XcodeGen 因空目录报错。

- [ ] **Step 1: 写 project.yml**

```yaml
# project.yml
name: ccMonitor
options:
  bundleIdPrefix: com.ccmonitor
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    PRODUCT_BUNDLE_IDENTIFIER: com.ccmonitor.app
    GENERATE_INFOPLIST_FILE: YES
    INFOPLIST_KEY_LSUIElement: YES          # 菜单栏 app，无 Dock 图标
    INFOPLIST_KEY_NSHumanReadableCopyright: ""
    CODE_SIGN_STYLE: Automatic
    ENABLE_HARDENED_RUNTIME: YES
targets:
  ccMonitor:
    type: application
    platform: macOS
    sources:
      - path: ccMonitor
    settings:
      base:
        OTHER_LDFLAGS: "-lsqlite3"          # 链接系统 SQLite
  ccMonitorTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: ccMonitorTests
    dependencies:
      - target: ccMonitor
    settings:
      base:
        OTHER_LDFLAGS: "-lsqlite3"
schemes:
  ccMonitor:
    build:
      targets:
        ccMonitor: all
        ccMonitorTests: [test]
    test:
      targets:
        - ccMonitorTests
    run:
      config: Debug
```

- [ ] **Step 2: 建占位源文件（XcodeGen 不接受空目录）**

```bash
mkdir -p ccMonitor ccMonitorTests
# 临时入口占位，Task 16 会替换
cat > ccMonitor/ccMonitorApp.swift <<'EOF'
import SwiftUI

@main
struct ccMonitorApp: App {
    var body: some Scene { Settings { EmptyView() } }
}
EOF
# 占位测试，Task 2 起逐个替换/新增
cat > ccMonitorTests/PlaceholderTests.swift <<'EOF'
import XCTest
final class PlaceholderTests: XCTestCase {
    func test_placeholder() { XCTAssertTrue(true) }
}
EOF
```

- [ ] **Step 3: 生成 .xcodeproj**

Run: `xcodegen generate`
Expected: 输出 `Created project at ...ccMonitor.xcodeproj`。

- [ ] **Step 4: 验证骨架能编译**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 验证占位测试能跑**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS'`
Expected: `TEST SUCCEEDED`（PlaceholderTests 通过）。

- [ ] **Step 6: 提交**

```bash
git add project.yml ccMonitor ccMonitorTests
git commit -m "chore: XcodeGen 声明式生成 ccMonitor 项目骨架(菜单栏 app)"
```

> **后续维护**：每次新增 .swift 文件后，需重跑 `xcodegen generate` 让文件进项目（XcodeGen 按目录扫描，无需手动拖文件）。各任务的"提交"前都隐含这一步——若新建了文件，先 `xcodegen generate` 再 `xcodebuild`。

---

## Task 2: 数字格式化纯函数（TDD）

**Files:**
- Create: `ccMonitor/Views/Components/Formatters.swift`
- Test: `ccMonitorTests/FormattersTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
// ccMonitorTests/FormattersTests.swift
import XCTest
@testable import ccMonitor

final class FormattersTests: XCTestCase {
    func test_formatTokens_millions() {
        XCTAssertEqual(formatTokens(1_234_567), "1.2M")
    }
    func test_formatTokens_thousands() {
        XCTAssertEqual(formatTokens(12_500), "12.5K")
    }
    func test_formatTokens_small() {
        XCTAssertEqual(formatTokens(842), "842")
    }
    func test_formatTokens_zero() {
        XCTAssertEqual(formatTokens(0), "0")
    }
    func test_formatCost() {
        XCTAssertEqual(formatCost(74.7382), "$74.74")
    }
    func test_formatCost_zero() {
        XCTAssertEqual(formatCost(0), "$0.00")
    }
    func test_formatPercent() {
        XCTAssertEqual(formatPercent(0.2345), "23%")
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/FormattersTests`
Expected: 编译失败（`formatTokens` 未定义）。

- [ ] **Step 3: 写最小实现**

```swift
// ccMonitor/Views/Components/Formatters.swift
import Foundation

func formatTokens(_ n: Int) -> String {
    let v = Double(n)
    if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
    return "\(n)"
}

func formatCost(_ usd: Double) -> String {
    return String(format: "$%.2f", usd)
}

func formatPercent(_ ratio: Double) -> String {
    return "\(Int((ratio * 100).rounded()))%"
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/FormattersTests`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add ccMonitor/Views/Components/Formatters.swift ccMonitorTests/FormattersTests.swift
git commit -m "feat: 数字/成本/百分比格式化函数"
```

---

## Task 3: 数据模型 + 价格类型（TDD 覆盖计算属性）

**Files:**
- Create: `ccMonitor/Models/UsageModels.swift`
- Create: `ccMonitor/Models/Pricing.swift`
- Test: `ccMonitorTests/PricingTests.swift`

- [ ] **Step 1: 写失败测试（缓存率 + 成本公式）**

```swift
// ccMonitorTests/PricingTests.swift
import XCTest
@testable import ccMonitor

final class PricingTests: XCTestCase {
    func test_modelUsage_monthTotal() {
        let u = ModelUsage(model: "m", monthInput: 100, monthOutput: 200,
                           monthCacheRead: 300, monthCacheCreate: 400, todayTotal: 50)
        XCTAssertEqual(u.monthTotal, 1000)
    }

    func test_cacheRate_formula() {
        // cache_read / (input + cache_read) = 300 / (100 + 300) = 0.75
        let u = ModelUsage(model: "m", monthInput: 100, monthOutput: 0,
                           monthCacheRead: 300, monthCacheCreate: 0, todayTotal: 0)
        XCTAssertEqual(u.cacheRate, 0.75, accuracy: 0.0001)
    }

    func test_cacheRate_zeroDenominator() {
        let u = ModelUsage(model: "m", monthInput: 0, monthOutput: 0,
                           monthCacheRead: 0, monthCacheCreate: 0, todayTotal: 0)
        XCTAssertEqual(u.cacheRate, 0)
    }

    func test_cost_recompute_perMillion() {
        // 单价 $/1M: in=3, out=15, cr=0.3, cc=3.75
        // cost = (1e6*3 + 1e6*15 + 1e6*0.3 + 1e6*3.75)/1e6 = 22.05
        let u = ModelUsage(model: "m", monthInput: 1_000_000, monthOutput: 1_000_000,
                           monthCacheRead: 1_000_000, monthCacheCreate: 1_000_000, todayTotal: 0)
        let p = ModelPricing(input: 3, output: 15, cacheRead: 0.3, cacheCreate: 3.75)
        XCTAssertEqual(u.cost(with: p), 22.05, accuracy: 0.0001)
    }

    func test_cost_defaultPricingIsZero() {
        let u = ModelUsage(model: "m", monthInput: 1_000_000, monthOutput: 1_000_000,
                           monthCacheRead: 0, monthCacheCreate: 0, todayTotal: 0)
        XCTAssertEqual(u.cost(with: ModelPricing()), 0)
    }

    func test_summaryStats_cacheRate() {
        let s = SummaryStats(input: 100, output: 50, cacheRead: 300, cacheCreate: 0)
        XCTAssertEqual(s.total, 450)
        XCTAssertEqual(s.cacheRate, 0.75, accuracy: 0.0001)
    }

    func test_pricing_codable_roundtrip() throws {
        let p = ModelPricing(input: 3, output: 15, cacheRead: 0.3, cacheCreate: 3.75)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(ModelPricing.self, from: data)
        XCTAssertEqual(back, p)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/PricingTests`
Expected: 编译失败（类型未定义）。

- [ ] **Step 3: 写实现**

```swift
// ccMonitor/Models/Pricing.swift
import Foundation

/// 单价，单位 $/1M token。默认全 0，由用户手动填。
struct ModelPricing: Codable, Equatable {
    var input: Double = 0
    var output: Double = 0
    var cacheRead: Double = 0
    var cacheCreate: Double = 0
}
```

```swift
// ccMonitor/Models/UsageModels.swift
import Foundation

/// ① 模型列表一行。本月口径 + 今日总量。
struct ModelUsage: Identifiable, Equatable {
    var id: String { model }
    let model: String
    let monthInput: Int
    let monthOutput: Int
    let monthCacheRead: Int
    let monthCacheCreate: Int
    let todayTotal: Int

    var monthTotal: Int { monthInput + monthOutput + monthCacheRead + monthCacheCreate }

    /// 缓存率 = cache_read / (input + cache_read)，本月口径。分母 0 → 0。
    var cacheRate: Double {
        let denom = monthInput + monthCacheRead
        return denom == 0 ? 0 : Double(monthCacheRead) / Double(denom)
    }

    /// 用用户单价重算成本（$/1M token），不读 db 成本字段。
    func cost(with p: ModelPricing) -> Double {
        (Double(monthInput) * p.input
         + Double(monthOutput) * p.output
         + Double(monthCacheRead) * p.cacheRead
         + Double(monthCacheCreate) * p.cacheCreate) / 1_000_000
    }
}

/// ② 汇总区，跟随时间范围，不分模型。
struct SummaryStats: Equatable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreate: Int

    var total: Int { input + output + cacheRead + cacheCreate }
    var cacheRate: Double {
        let denom = input + cacheRead
        return denom == 0 ? 0 : Double(cacheRead) / Double(denom)
    }

    static let empty = SummaryStats(input: 0, output: 0, cacheRead: 0, cacheCreate: 0)
}

/// ③ 折线图一个点。
struct TrendPoint: Identifiable, Equatable {
    var id: String { day + "|" + model }
    let day: String        // yyyy-MM-dd
    let model: String
    let total: Int
}

/// ④ 热力图一格。level 在 View 层按全局 max 动态分档。
struct HeatmapDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let total: Int
}

/// 顶部时间范围按钮。
enum TimeRange: Equatable {
    case today
    case last7d
    case last30d
    case custom(Date, Date)
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/PricingTests`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add ccMonitor/Models/
git commit -m "feat: 用量/汇总/趋势/热力图数据模型与价格类型"
```

---

## Task 4: 时间窗端点计算（TDD）

**Files:**
- Create: `ccMonitor/Data/DateWindows.swift`
- Test: `ccMonitorTests/DateWindowsTests.swift`

时间窗返回 `(start, end)` 的 Unix 秒（`Int`），半开区间 `[start, end)`。用 `Calendar.current`（本地时区）。为测试可控，函数接受 `now: Date` 与 `calendar: Calendar` 参数。

- [ ] **Step 1: 写失败测试**

```swift
// ccMonitorTests/DateWindowsTests.swift
import XCTest
@testable import ccMonitor

final class DateWindowsTests: XCTestCase {
    // 固定一个参考时刻：2026-06-14 17:30:00 本地时间
    private func makeCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    private func date(_ y: Int,_ mo: Int,_ d: Int,_ h: Int = 0,_ mi: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        return makeCalendar().date(from: comps)!
    }

    func test_todayWindow_startIsMidnight_endIsNextMidnight() {
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.today(now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 6, 14, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 15, 0, 0).timeIntervalSince1970))
    }

    func test_monthWindow_startIsFirstOfMonth() {
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.thisMonth(now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 6, 1, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 7, 1, 0, 0).timeIntervalSince1970))
    }

    func test_lastNDays_7d_startIs6DaysBeforeTodayMidnight() {
        // 最近7天 = 含今天在内往前7天，start = 今天-6 的 00:00
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.lastDays(7, now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 6, 8, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 15, 0, 0).timeIntervalSince1970))
    }

    func test_lastNDays_30d() {
        let now = date(2026, 6, 14, 17, 30)
        let w = DateWindows.lastDays(30, now: now, calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 5, 16, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 15, 0, 0).timeIntervalSince1970))
    }

    func test_customWindow_inclusiveEndDay() {
        // 自定义 [6/1, 6/3]，end 应到 6/4 的 00:00（含 6/3 全天）
        let w = DateWindows.custom(from: date(2026, 6, 1), to: date(2026, 6, 3),
                                   calendar: makeCalendar())
        XCTAssertEqual(w.start, Int(date(2026, 6, 1, 0, 0).timeIntervalSince1970))
        XCTAssertEqual(w.end, Int(date(2026, 6, 4, 0, 0).timeIntervalSince1970))
    }

    func test_resolve_dispatchesByRange() {
        let now = date(2026, 6, 14, 17, 30)
        let cal = makeCalendar()
        XCTAssertEqual(DateWindows.resolve(.today, now: now, calendar: cal).start,
                       DateWindows.today(now: now, calendar: cal).start)
        XCTAssertEqual(DateWindows.resolve(.last7d, now: now, calendar: cal).start,
                       DateWindows.lastDays(7, now: now, calendar: cal).start)
        XCTAssertEqual(DateWindows.resolve(.last30d, now: now, calendar: cal).start,
                       DateWindows.lastDays(30, now: now, calendar: cal).start)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/DateWindowsTests`
Expected: 编译失败（`DateWindows` 未定义）。

- [ ] **Step 3: 写实现**

```swift
// ccMonitor/Data/DateWindows.swift
import Foundation

/// 时间窗端点，半开区间 [start, end) 的 Unix 秒。
struct DateWindow: Equatable {
    let start: Int
    let end: Int
}

enum DateWindows {
    private static func unix(_ d: Date) -> Int { Int(d.timeIntervalSince1970) }

    /// 今日 00:00 ..< 次日 00:00
    static func today(now: Date, calendar: Calendar) -> DateWindow {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 本月 1 号 00:00 ..< 下月 1 号 00:00
    static func thisMonth(now: Date, calendar: Calendar) -> DateWindow {
        let comps = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: comps)!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 最近 n 天（含今天）：start = (今天 - (n-1)) 的 00:00，end = 次日 00:00
    static func lastDays(_ n: Int, now: Date, calendar: Calendar) -> DateWindow {
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(n - 1), to: todayStart)!
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 自定义 [from, to]，含 to 当天全天：start = from 当天 00:00，end = to 次日 00:00
    static func custom(from: Date, to: Date, calendar: Calendar) -> DateWindow {
        let start = calendar.startOfDay(for: from)
        let toStart = calendar.startOfDay(for: to)
        let end = calendar.date(byAdding: .day, value: 1, to: toStart)!
        return DateWindow(start: unix(start), end: unix(end))
    }

    /// 按 TimeRange 分派（汇总区用）。
    static func resolve(_ range: TimeRange, now: Date, calendar: Calendar) -> DateWindow {
        switch range {
        case .today: return today(now: now, calendar: calendar)
        case .last7d: return lastDays(7, now: now, calendar: calendar)
        case .last30d: return lastDays(30, now: now, calendar: calendar)
        case .custom(let f, let t): return custom(from: f, to: t, calendar: calendar)
        }
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/DateWindowsTests`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add ccMonitor/Data/DateWindows.swift ccMonitorTests/DateWindowsTests.swift
git commit -m "feat: 时间窗端点计算(今日/本月/最近N天/自定义)"
```

---

## Task 5: SQLite 只读封装（TDD）

**Files:**
- Create: `ccMonitor/Data/SQLiteDatabase.swift`
- Test: `ccMonitorTests/UsageRepositoryTests.swift`（本任务先建文件，测 SQLiteDatabase 基础能力）

薄封装：只读打开、prepare、绑定 Int 参数、按列取 Int/String/Double、step 遍历、finalize。失败抛 Swift 错误，不崩溃。

- [ ] **Step 1: 写失败测试（建临时库 + 基本查询）**

```swift
// ccMonitorTests/UsageRepositoryTests.swift
import XCTest
@testable import ccMonitor

final class UsageRepositoryTests: XCTestCase {
    /// 在临时目录建一个含 proxy_request_logs 表的库，返回路径。
    func makeTempDB(rows: [(model: String, created: Int, i: Int, o: Int, cr: Int, cc: Int)]) throws -> String {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("ccm_test_\(UUID().uuidString).db")
        let db = try SQLiteDatabase(path: path, readonly: false)
        try db.exec("""
            CREATE TABLE proxy_request_logs (
                request_id TEXT, provider_id TEXT, app_type TEXT, model TEXT,
                input_tokens INTEGER, output_tokens INTEGER,
                cache_read_tokens INTEGER, cache_creation_tokens INTEGER,
                total_cost_usd TEXT, latency_ms INTEGER, status_code INTEGER,
                created_at INTEGER, data_source TEXT
            );
        """)
        for r in rows {
            try db.exec("""
                INSERT INTO proxy_request_logs
                (request_id, provider_id, app_type, model, input_tokens, output_tokens,
                 cache_read_tokens, cache_creation_tokens, total_cost_usd, latency_ms,
                 status_code, created_at, data_source)
                VALUES ('r','_session','claude','\(r.model)', \(r.i), \(r.o), \(r.cr), \(r.cc),
                        '0', 0, 200, \(r.created), 'session_log');
            """)
        }
        db.close()
        return path
    }

    func test_open_readonly_existing() throws {
        let path = try makeTempDB(rows: [("m", 1000, 1, 2, 3, 4)])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path, readonly: true)
        defer { db.close() }
        let count = try db.queryScalarInt("SELECT COUNT(*) FROM proxy_request_logs;")
        XCTAssertEqual(count, 1)
    }

    func test_open_missingFile_throws() {
        XCTAssertThrowsError(try SQLiteDatabase(path: "/nonexistent/xx.db", readonly: true))
    }

    func test_queryRows_withParams() throws {
        let path = try makeTempDB(rows: [
            ("a", 100, 1, 0, 0, 0),
            ("b", 200, 2, 0, 0, 0),
            ("a", 300, 4, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path, readonly: true)
        defer { db.close() }
        var got: [(String, Int)] = []
        try db.query(
            "SELECT model, SUM(input_tokens) FROM proxy_request_logs WHERE created_at >= ? AND created_at < ? GROUP BY model ORDER BY model;",
            ints: [150, 400]
        ) { row in
            got.append((row.string(0) ?? "", row.int(1)))
        }
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got[0].0, "a"); XCTAssertEqual(got[0].1, 4)
        XCTAssertEqual(got[1].0, "b"); XCTAssertEqual(got[1].1, 2)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/UsageRepositoryTests/test_open_readonly_existing`
Expected: 编译失败（`SQLiteDatabase` 未定义）。

- [ ] **Step 3: 写实现**

```swift
// ccMonitor/Data/SQLiteDatabase.swift
import Foundation
import SQLite3

enum SQLiteError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case execFailed(String)
}

/// 一行查询结果的列访问器。
struct SQLiteRow {
    fileprivate let stmt: OpaquePointer
    func int(_ col: Int32) -> Int { Int(sqlite3_column_int64(stmt, col)) }
    func double(_ col: Int32) -> Double { sqlite3_column_double(stmt, col) }
    func string(_ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }
}

/// SQLite C API 薄封装。只读模式用于读 cc-switch.db。
final class SQLiteDatabase {
    private var db: OpaquePointer?
    // 让字符串绑定在 sqlite 拷贝前保持存活
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String, readonly: Bool) throws {
        let flags = readonly
            ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX)
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw SQLiteError.openFailed(msg)
        }
        sqlite3_busy_timeout(db, 2000) // 与 cc-switch 写入冲突时等待
    }

    func close() {
        if db != nil { sqlite3_close(db); db = nil }
    }

    /// 执行无返回值 SQL（建表/插入，测试用）。
    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError.execFailed(msg)
        }
    }

    /// 查询并逐行回调。ints 按位置绑定到 ? 占位符。
    func query(_ sql: String, ints: [Int] = [], _ rowHandler: (SQLiteRow) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (idx, v) in ints.enumerated() {
            sqlite3_bind_int64(stmt, Int32(idx + 1), Int64(v))
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            rowHandler(SQLiteRow(stmt: stmt!))
        }
    }

    /// 查询单个整数标量。
    func queryScalarInt(_ sql: String, ints: [Int] = []) throws -> Int {
        var result = 0
        try query(sql, ints: ints) { row in result = row.int(0) }
        return result
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/UsageRepositoryTests/test_open_readonly_existing -only-testing:ccMonitorTests/UsageRepositoryTests/test_open_missingFile_throws -only-testing:ccMonitorTests/UsageRepositoryTests/test_queryRows_withParams`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add ccMonitor/Data/SQLiteDatabase.swift ccMonitorTests/UsageRepositoryTests.swift
git commit -m "feat: SQLite 只读薄封装(open/exec/query/scalar)"
```

---

## Task 6: UsageRepository 聚合查询（TDD，核心）

**Files:**
- Create: `ccMonitor/Data/UsageRepository.swift`
- Test: `ccMonitorTests/UsageRepositoryTests.swift`（追加测试）

Repository 持有 dbPath，每次查询开只读连接、查完关闭。提供：模型列表（本月+今日合并）、汇总、趋势（30天）、热力图（按天）、distinct 模型名。

- [ ] **Step 1: 追加失败测试**

在 `UsageRepositoryTests.swift` 的 class 内追加：

```swift
    func test_fetchModelUsages_mergesMonthAndToday_sortedDesc() throws {
        // today=2026-06-14 区间用真实端点；构造两条本月数据 + 一条今日数据
        let cal = Calendar.current
        let now = Date()
        let month = DateWindows.thisMonth(now: now, calendar: cal)
        let today = DateWindows.today(now: now, calendar: cal)
        // 本月内但非今日的一条（放在本月起点）
        let monthOnlyTs = month.start + 60
        // 今日的一条
        let todayTs = today.start + 60
        let path = try makeTempDB(rows: [
            ("big",   monthOnlyTs, 1000, 0, 0, 0),
            ("big",   todayTs,      500, 0, 0, 0),   // big 今日 500
            ("small", monthOnlyTs,  100, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let repo = UsageRepository(dbPath: path)
        let usages = try repo.fetchModelUsages(now: now, calendar: cal)

        XCTAssertEqual(usages.count, 2)
        // 按本月用量降序：big(1500) 在前，small(100) 在后
        XCTAssertEqual(usages[0].model, "big")
        XCTAssertEqual(usages[0].monthInput, 1500)
        XCTAssertEqual(usages[0].todayTotal, 500)
        XCTAssertEqual(usages[1].model, "small")
        XCTAssertEqual(usages[1].todayTotal, 0)
    }

    func test_fetchSummary_forWindow() throws {
        let path = try makeTempDB(rows: [
            ("a", 1000, 10, 20, 30, 40),
            ("b", 1000, 1, 2, 3, 4),
            ("c", 9_999_999_999, 999, 0, 0, 0), // 区间外
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        let s = try repo.fetchSummary(window: DateWindow(start: 0, end: 2000))
        XCTAssertEqual(s.input, 11)
        XCTAssertEqual(s.output, 22)
        XCTAssertEqual(s.cacheRead, 33)
        XCTAssertEqual(s.cacheCreate, 44)
    }

    func test_fetchTrend_groupsByDayAndModel() throws {
        // 两天，两个模型
        let d1 = 1_780_000_000 // 某天
        let d2 = d1 + 86_400
        let path = try makeTempDB(rows: [
            ("a", d1, 5, 0, 0, 0),
            ("a", d1, 5, 0, 0, 0), // 同天同模型累加 → 10
            ("b", d1, 1, 0, 0, 0),
            ("a", d2, 7, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        let pts = try repo.fetchTrend(window: DateWindow(start: d1 - 10, end: d2 + 86_400))
        // a 在 d1 应为 10
        let aDay1 = pts.first { $0.model == "a" && $0.total == 10 }
        XCTAssertNotNil(aDay1)
        // 至少有 a@d1, b@d1, a@d2 三个点
        XCTAssertGreaterThanOrEqual(pts.count, 3)
    }

    func test_fetchHeatmap_sumsPerDay() throws {
        let d1 = 1_780_000_000
        let path = try makeTempDB(rows: [
            ("a", d1, 5, 5, 0, 0),   // 当天总 10
            ("b", d1, 1, 1, 1, 1),   // 当天再 +4 → 14
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        let days = try repo.fetchHeatmap(window: DateWindow(start: d1 - 10, end: d1 + 86_400))
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].total, 14)
    }

    func test_fetchDistinctModels_sorted() throws {
        let path = try makeTempDB(rows: [
            ("zeta", 1, 1, 0, 0, 0),
            ("alpha", 2, 1, 0, 0, 0),
            ("alpha", 3, 1, 0, 0, 0),
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = UsageRepository(dbPath: path)
        XCTAssertEqual(try repo.fetchDistinctModels(), ["alpha", "zeta"])
    }

    func test_missingDB_throwsNotCrash() {
        let repo = UsageRepository(dbPath: "/nonexistent/x.db")
        XCTAssertThrowsError(try repo.fetchSummary(window: DateWindow(start: 0, end: 1)))
    }
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/UsageRepositoryTests/test_fetchSummary_forWindow`
Expected: 编译失败（`UsageRepository` 未定义）。

- [ ] **Step 3: 写实现**

```swift
// ccMonitor/Data/UsageRepository.swift
import Foundation

/// 所有聚合查询。每次开只读连接，查完关闭。失败抛错，不崩溃。
struct UsageRepository {
    let dbPath: String

    private func withDB<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        let db = try SQLiteDatabase(path: dbPath, readonly: true)
        defer { db.close() }
        return try body(db)
    }

    /// ① 模型列表：本月按 model 聚合 + 今日总量合并，按本月用量降序。
    func fetchModelUsages(now: Date, calendar: Calendar) throws -> [ModelUsage] {
        let month = DateWindows.thisMonth(now: now, calendar: calendar)
        let today = DateWindows.today(now: now, calendar: calendar)

        return try withDB { db in
            // 本月：每模型四类
            var monthRows: [(String, Int, Int, Int, Int)] = []
            try db.query("""
                SELECT model, SUM(input_tokens), SUM(output_tokens),
                       SUM(cache_read_tokens), SUM(cache_creation_tokens)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY model;
            """, ints: [month.start, month.end]) { row in
                monthRows.append((row.string(0) ?? "", row.int(1), row.int(2), row.int(3), row.int(4)))
            }

            // 今日：每模型总量
            var todayMap: [String: Int] = [:]
            try db.query("""
                SELECT model,
                       SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY model;
            """, ints: [today.start, today.end]) { row in
                todayMap[row.string(0) ?? ""] = row.int(1)
            }

            let usages = monthRows.map { r in
                ModelUsage(model: r.0, monthInput: r.1, monthOutput: r.2,
                           monthCacheRead: r.3, monthCacheCreate: r.4,
                           todayTotal: todayMap[r.0] ?? 0)
            }
            return usages.sorted { $0.monthTotal > $1.monthTotal }
        }
    }

    /// ② 汇总：给定窗口的四类 token 总和。
    func fetchSummary(window: DateWindow) throws -> SummaryStats {
        try withDB { db in
            var s = SummaryStats.empty
            try db.query("""
                SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0),
                       COALESCE(SUM(cache_read_tokens),0), COALESCE(SUM(cache_creation_tokens),0)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?;
            """, ints: [window.start, window.end]) { row in
                s = SummaryStats(input: row.int(0), output: row.int(1),
                                 cacheRead: row.int(2), cacheCreate: row.int(3))
            }
            return s
        }
    }

    /// ③ 趋势：按天 × 模型聚合总 token。
    func fetchTrend(window: DateWindow) throws -> [TrendPoint] {
        try withDB { db in
            var pts: [TrendPoint] = []
            try db.query("""
                SELECT date(created_at,'unixepoch','localtime') AS day, model,
                       SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY day, model ORDER BY day;
            """, ints: [window.start, window.end]) { row in
                pts.append(TrendPoint(day: row.string(0) ?? "", model: row.string(1) ?? "", total: row.int(2)))
            }
            return pts
        }
    }

    /// ④ 热力图：按天聚合总 token。
    func fetchHeatmap(window: DateWindow) throws -> [HeatmapDay] {
        try withDB { db in
            var days: [HeatmapDay] = []
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.timeZone = TimeZone.current
            try db.query("""
                SELECT date(created_at,'unixepoch','localtime') AS day,
                       SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens)
                FROM proxy_request_logs
                WHERE created_at >= ? AND created_at < ?
                GROUP BY day ORDER BY day;
            """, ints: [window.start, window.end]) { row in
                guard let d = fmt.date(from: row.string(0) ?? "") else { return }
                days.append(HeatmapDay(date: d, total: row.int(1)))
            }
            return days
        }
    }

    /// 设置面板用：所有有历史数据的模型名。
    func fetchDistinctModels() throws -> [String] {
        try withDB { db in
            var models: [String] = []
            try db.query("SELECT DISTINCT model FROM proxy_request_logs ORDER BY model;") { row in
                if let m = row.string(0) { models.append(m) }
            }
            return models
        }
    }
}
```

- [ ] **Step 4: 运行全部 Repository 测试，确认通过**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -only-testing:ccMonitorTests/UsageRepositoryTests`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add ccMonitor/Data/UsageRepository.swift ccMonitorTests/UsageRepositoryTests.swift
git commit -m "feat: UsageRepository 聚合查询(模型/汇总/趋势/热力图/模型列表)"
```

---

## Task 7: SettingsStore 与 PricingStore（UserDefaults 持久化）

**Files:**
- Create: `ccMonitor/Stores/SettingsStore.swift`
- Create: `ccMonitor/Stores/PricingStore.swift`

这两个是 UserDefaults 包装，逻辑简单，不强制 TDD（但 PricingStore 的 Codable 往返已在 Task 3 测过）。用 Preview/手动验证即可。

- [ ] **Step 1: 写 SettingsStore**

```swift
// ccMonitor/Stores/SettingsStore.swift
import Foundation
import Combine

final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let dbPath = "dbPath"
        static let refreshInterval = "refreshIntervalMinutes"
    }

    static var defaultDBPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".cc-switch/cc-switch.db")
    }

    @Published var dbPath: String {
        didSet { defaults.set(dbPath, forKey: Keys.dbPath) }
    }
    /// 允许值：5/10/15/30
    @Published var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshInterval) }
    }

    init() {
        self.dbPath = defaults.string(forKey: Keys.dbPath) ?? SettingsStore.defaultDBPath
        let saved = defaults.integer(forKey: Keys.refreshInterval)
        self.refreshIntervalMinutes = saved == 0 ? 5 : saved
    }
}
```

- [ ] **Step 2: 写 PricingStore**

```swift
// ccMonitor/Stores/PricingStore.swift
import Foundation
import Combine

final class PricingStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let key = "modelPricing"

    /// [模型名: 单价]
    @Published var pricing: [String: ModelPricing] {
        didSet { persist() }
    }

    init() {
        if let data = defaults.data(forKey: key),
           let map = try? JSONDecoder().decode([String: ModelPricing].self, from: data) {
            self.pricing = map
        } else {
            self.pricing = [:]
        }
    }

    func pricing(for model: String) -> ModelPricing {
        pricing[model] ?? ModelPricing()
    }

    func setPricing(_ p: ModelPricing, for model: String) {
        pricing[model] = p
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pricing) {
            defaults.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 提交**

```bash
git add ccMonitor/Stores/SettingsStore.swift ccMonitor/Stores/PricingStore.swift
git commit -m "feat: 设置与价格持久化(UserDefaults)"
```

---

## Task 8: DataStore 状态中枢 + 定时刷新

**Files:**
- Create: `ccMonitor/Stores/DataStore.swift`

DataStore 持有 settings/pricing，暴露 `@Published` 数据给 View，按间隔定时刷新，时间范围切换时只重查汇总。所有 db 读取放后台队列，结果回主线程。

- [ ] **Step 1: 写 DataStore**

```swift
// ccMonitor/Stores/DataStore.swift
import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    @Published var modelUsages: [ModelUsage] = []
    @Published var summary: SummaryStats = .empty
    @Published var trend: [TrendPoint] = []
    @Published var heatmap: [HeatmapDay] = []
    @Published var loadError: String?
    @Published var isLoading = false

    @Published var selectedRange: TimeRange = .today {
        didSet { Task { await refreshSummary() } }
    }

    let settings: SettingsStore
    let pricing: PricingStore
    private var timer: Timer?

    init(settings: SettingsStore, pricing: PricingStore) {
        self.settings = settings
        self.pricing = pricing
    }

    private var repo: UsageRepository { UsageRepository(dbPath: settings.dbPath) }

    /// 全量刷新（模型列表 + 汇总 + 趋势 + 热力图）。
    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        let repo = self.repo
        let range = self.selectedRange
        let now = Date()
        let cal = Calendar.current

        do {
            let (usages, summary, trend, heat) = try await Task.detached(priority: .userInitiated) {
                let summaryWindow = DateWindows.resolve(range, now: now, calendar: cal)
                let trendWindow = DateWindows.lastDays(30, now: now, calendar: cal)
                let heatWindow = DateWindows.lastDays(52 * 7, now: now, calendar: cal)
                return (
                    try repo.fetchModelUsages(now: now, calendar: cal),
                    try repo.fetchSummary(window: summaryWindow),
                    try repo.fetchTrend(window: trendWindow),
                    try repo.fetchHeatmap(window: heatWindow)
                )
            }.value
            self.modelUsages = usages
            self.summary = summary
            self.trend = trend
            self.heatmap = heat
            self.loadError = nil
        } catch {
            self.loadError = describe(error)
        }
    }

    /// 仅刷新汇总（时间范围切换时）。
    func refreshSummary() async {
        let repo = self.repo
        let range = self.selectedRange
        let now = Date()
        let cal = Calendar.current
        do {
            let s = try await Task.detached(priority: .userInitiated) {
                try repo.fetchSummary(window: DateWindows.resolve(range, now: now, calendar: cal))
            }.value
            self.summary = s
            self.loadError = nil
        } catch {
            self.loadError = describe(error)
        }
    }

    func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(settings.refreshIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
    }

    func stopTimer() { timer?.invalidate(); timer = nil }

    private func describe(_ error: Error) -> String {
        if case SQLiteError.openFailed = error {
            return "未找到数据库或无法打开，请在设置中检查路径"
        }
        return "读取失败：\(error.localizedDescription)"
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 提交**

```bash
git add ccMonitor/Stores/DataStore.swift
git commit -m "feat: DataStore 状态中枢与定时刷新"
```

---

## Task 9: 进度条与时间范围选择器组件

**Files:**
- Create: `ccMonitor/Views/Components/UsageProgressBar.swift`
- Create: `ccMonitor/Views/Components/TimeRangeSelector.swift`

UI 组件用 `#Preview` 目视验证。

- [ ] **Step 1: 写 UsageProgressBar（圆角进度条 + 黑色叠加文字）**

```swift
// ccMonitor/Views/Components/UsageProgressBar.swift
import SwiftUI

/// 圆角进度条：蓝色渐变填充 + 黑色加粗叠加文字（对比度硬性要求）。
struct UsageProgressBar: View {
    let fraction: Double      // 0...1
    let text: String          // 叠加显示的文字，如 "12.5K / 1.2M"
    var height: CGFloat = 14
    var gradient = LinearGradient(colors: [Color(hex: 0x2196F3), Color(hex: 0x21CBF3)],
                                  startPoint: .leading, endPoint: .trailing)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color(hex: 0xE0E0E0))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(gradient)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)   // 黑色，任意背景对比度
            }
        }
        .frame(height: height)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

#Preview {
    VStack(spacing: 12) {
        UsageProgressBar(fraction: 0.32, text: "12.5K / 39K")
        UsageProgressBar(fraction: 0.75, text: "750K / 1.0M")
        UsageProgressBar(fraction: 0.05, text: "5K / 100K")
    }
    .padding()
    .frame(width: 380)
}
```

- [ ] **Step 2: 写 TimeRangeSelector**

```swift
// ccMonitor/Views/Components/TimeRangeSelector.swift
import SwiftUI

/// 顶部时间范围按钮组：当日 / 7d / 30d / 自定义。
struct TimeRangeSelector: View {
    @Binding var selected: TimeRange
    let onCustomTap: () -> Void

    private func isActive(_ r: TimeRange) -> Bool {
        switch (selected, r) {
        case (.today, .today), (.last7d, .last7d), (.last30d, .last30d): return true
        case (.custom, .custom): return true
        default: return false
        }
    }

    private func chip(_ title: String, _ range: TimeRange, custom: Bool = false) -> some View {
        Button(action: {
            if custom { onCustomTap() } else { selected = range }
        }) {
            Text(title)
                .font(.system(size: 12))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isActive(range) ? Color(hex: 0x2196F3) : Color(hex: 0xF0F0F0))
                .foregroundColor(isActive(range) ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 6) {
            chip("当日", .today)
            chip("7天", .last7d)
            chip("30天", .last30d)
            chip("自定义", .custom(Date(), Date()), custom: true)
            Spacer()
        }
    }
}

#Preview {
    StatefulPreviewWrapper(TimeRange.today) { binding in
        TimeRangeSelector(selected: binding, onCustomTap: {})
            .padding().frame(width: 380)
    }
}

/// Preview 辅助：让 @Binding 在 Preview 里可变。
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(_ initial: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial); self.content = content
    }
    var body: some View { content($value) }
}
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 在 Xcode 打开两个文件，确认 Canvas Preview 正常显示**

- [ ] **Step 5: 提交**

```bash
git add ccMonitor/Views/Components/UsageProgressBar.swift ccMonitor/Views/Components/TimeRangeSelector.swift
git commit -m "feat: 进度条与时间范围选择器组件"
```

---

## Task 10: 模型列表视图（①）

**Files:**
- Create: `ccMonitor/Views/ModelListView.swift`

- [ ] **Step 1: 写 ModelListView**

```swift
// ccMonitor/Views/ModelListView.swift
import SwiftUI

/// ① 模型列表：每行 模型名 + 缓存率 + 成本 + 进度条(今日/本月)。
struct ModelListView: View {
    let usages: [ModelUsage]
    let pricing: PricingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(usages) { u in
                VStack(spacing: 8) {
                    HStack {
                        Text(u.model)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("缓存率: \(formatPercent(u.cacheRate))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: 0xFFC107))
                        Text("成本: \(formatCost(u.cost(with: pricing.pricing(for: u.model))))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: 0x4CAF50))
                    }
                    UsageProgressBar(
                        fraction: u.monthTotal == 0 ? 0 : Double(u.todayTotal) / Double(u.monthTotal),
                        text: "\(formatTokens(u.todayTotal)) / \(formatTokens(u.monthTotal))"
                    )
                }
                .padding(12)
                .background(Color(hex: 0xFAFAFA))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xEEEEEE)))
            }
        }
    }
}

#Preview {
    let pricing = PricingStore()
    return ModelListView(usages: [
        ModelUsage(model: "claude-sonnet-4-6", monthInput: 334848, monthOutput: 4195578,
                   monthCacheRead: 333630681, monthCacheCreate: 33315399, todayTotal: 120000),
        ModelUsage(model: "deepseek-v4-pro", monthInput: 5816761, monthOutput: 1644166,
                   monthCacheRead: 270605312, monthCacheCreate: 0, todayTotal: 30000),
    ], pricing: pricing)
    .padding().frame(width: 420)
}
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: Xcode Canvas 确认 Preview 显示模型行、进度条黑色文字清晰**

- [ ] **Step 4: 提交**

```bash
git add ccMonitor/Views/ModelListView.swift
git commit -m "feat: 模型列表视图(模型名/缓存率/成本/进度条)"
```

---

## Task 11: 汇总统计视图（②）

**Files:**
- Create: `ccMonitor/Views/SummaryView.swift`

- [ ] **Step 1: 写 SummaryView**

```swift
// ccMonitor/Views/SummaryView.swift
import SwiftUI

/// ② 时间范围按钮 + 汇总(总token大字 / 输入/输出/缓存 三列 / 缓存率进度条)。
struct SummaryView: View {
    @Binding var selectedRange: TimeRange
    let summary: SummaryStats
    let onCustomTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            TimeRangeSelector(selected: $selectedRange, onCustomTap: onCustomTap)

            VStack(spacing: 12) {
                Text(formatTokens(summary.total))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: 0x2196F3))

                HStack {
                    statCol(formatTokens(summary.input), "输入Token")
                    Spacer()
                    statCol(formatTokens(summary.output), "输出Token")
                    Spacer()
                    statCol(formatTokens(summary.cacheRead + summary.cacheCreate), "缓存Token")
                }

                // 缓存率进度条（琥珀渐变 + 黑字）
                UsageProgressBar(
                    fraction: summary.cacheRate,
                    text: "缓存率: \(formatPercent(summary.cacheRate))",
                    height: 12,
                    gradient: LinearGradient(colors: [Color(hex: 0xFFC107), Color(hex: 0xFFA000)],
                                             startPoint: .leading, endPoint: .trailing)
                )
            }
            .padding(16)
            .background(Color(hex: 0xF0F8FF))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0E6FF)))
        }
    }

    private func statCol(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .semibold))
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}

#Preview {
    StatefulPreviewWrapper(TimeRange.today) { binding in
        SummaryView(
            selectedRange: binding,
            summary: SummaryStats(input: 1224276, output: 987654, cacheRead: 200000, cacheCreate: 36622),
            onCustomTap: {}
        )
        .padding().frame(width: 420)
    }
}
```

- [ ] **Step 2: 编译 + Canvas 验证**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 提交**

```bash
git add ccMonitor/Views/SummaryView.swift
git commit -m "feat: 汇总统计视图(总量/三列/缓存率进度条)"
```

---

## Task 12: 折线图视图（③，Swift Charts）

**Files:**
- Create: `ccMonitor/Views/TrendChartView.swift`

固定最近 30 天，每模型一条彩色线，悬停显示该天全部模型名+值。

> **实现备注**：下面用 `proxy.value(atX:)` 取悬停日期。X 轴是 category（String 日期），在 macOS 13 上 category 轴的 `value(atX:)` 支持有限，可能取不到值。本机为 macOS 26 不受影响。若需兼容低版本，降级方案：用 `location.x` 除以每点宽度算出索引，映射到排序后的 distinct day 数组。

- [ ] **Step 1: 写 TrendChartView**

```swift
// ccMonitor/Views/TrendChartView.swift
import SwiftUI
import Charts

/// ③ 最近30天用量趋势，多模型多色线，悬停显示当天全部模型。
struct TrendChartView: View {
    let points: [TrendPoint]

    // 悬停选中的某一天
    @State private var selectedDay: String?

    private var models: [String] {
        Array(Set(points.map { $0.model })).sorted()
    }
    private var daySelection: [TrendPoint] {
        guard let d = selectedDay else { return [] }
        return points.filter { $0.day == d }.sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近30天用量趋势").font(.system(size: 14, weight: .semibold))

            Chart {
                ForEach(points) { p in
                    LineMark(
                        x: .value("日期", p.day),
                        y: .value("Token", p.total)
                    )
                    .foregroundStyle(by: .value("模型", p.model))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale(range: palette(models.count))
            .chartLegend(position: .bottom, spacing: 4)
            .frame(height: 140)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let day: String = proxy.value(atX: location.x - geo[proxy.plotAreaFrame].origin.x) {
                                    selectedDay = day
                                }
                            case .ended:
                                selectedDay = nil
                            }
                        }
                }
            }

            // 悬停信息：当天全部模型名+值
            if !daySelection.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay ?? "").font(.system(size: 11, weight: .bold))
                    ForEach(daySelection) { p in
                        Text("\(p.model): \(formatTokens(p.total))")
                            .font(.system(size: 11))
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.8))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(16)
        .background(Color(hex: 0xFAFAFA))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xEEEEEE)))
    }

    private func palette(_ n: Int) -> [Color] {
        let base: [Color] = [0x2196F3, 0x4CAF50, 0xFF9800, 0xE91E63, 0x9C27B0,
                             0x00BCD4, 0x795548, 0x607D8B, 0xCDDC39, 0xFF5722].map { Color(hex: $0) }
        return Array((0..<max(1, n)).map { base[$0 % base.count] })
    }
}

#Preview {
    let days = ["2026-06-10", "2026-06-11", "2026-06-12", "2026-06-13"]
    var pts: [TrendPoint] = []
    for (i, d) in days.enumerated() {
        pts.append(TrendPoint(day: d, model: "claude-sonnet-4-6", total: 1_000_000 * (i + 1)))
        pts.append(TrendPoint(day: d, model: "deepseek-v4-pro", total: 500_000 * (i + 2)))
    }
    return TrendChartView(points: pts).padding().frame(width: 420)
}
```

- [ ] **Step 2: 编译 + Canvas 验证（多色线 + 图例）**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 提交**

```bash
git add ccMonitor/Views/TrendChartView.swift
git commit -m "feat: 折线图视图(Swift Charts 多模型趋势+悬停)"
```

---

## Task 13: 热力图视图（④）

**Files:**
- Create: `ccMonitor/Views/HeatmapView.swift`

7 行 × 52 列圆角方块，按日总 token 动态分 5 档着色，底部标月份。

- [ ] **Step 1: 写 HeatmapView**

```swift
// ccMonitor/Views/HeatmapView.swift
import SwiftUI

/// ④ 7×52 热力图，按日总token分5档(无活动=灰)。
struct HeatmapView: View {
    let days: [HeatmapDay]      // 任意区间，内部按周排布

    private let weeks = 52
    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    // 用字典快速按日期取总量
    private var totalByDay: [String: Int] {
        let f = Self.dayFormatter
        return Dictionary(days.map { (f.string(from: $0.date), $0.total) }, uniquingKeysWith: +)
    }
    private var maxTotal: Int { days.map { $0.total }.max() ?? 0 }

    // 生成最近 52*7 天的日期网格（列=周，行=周日..周六）
    private var grid: [[Date]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // 找到本周的周日作为最后一列起点
        let weekday = cal.component(.weekday, from: today) // 1=周日
        let lastSunday = cal.date(byAdding: .day, value: -(weekday - 1), to: today)!
        var cols: [[Date]] = []
        for w in stride(from: weeks - 1, through: 0, by: -1) {
            let colStart = cal.date(byAdding: .day, value: -w * 7, to: lastSunday)!
            var col: [Date] = []
            for d in 0..<7 {
                col.append(cal.date(byAdding: .day, value: d, to: colStart)!)
            }
            cols.append(col)
        }
        return cols
    }

    private func level(_ total: Int) -> Int {
        guard total > 0, maxTotal > 0 else { return 0 }
        let r = Double(total) / Double(maxTotal)
        if r > 0.66 { return 4 }
        if r > 0.33 { return 3 }
        if r > 0.1 { return 2 }
        return 1
    }

    private func color(_ lvl: Int) -> Color {
        switch lvl {
        case 1: return Color(hex: 0xD6E685)
        case 2: return Color(hex: 0x8CC665)
        case 3: return Color(hex: 0x44A340)
        case 4: return Color(hex: 0x1E6823)
        default: return Color(hex: 0xE0E0E0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token活动").font(.system(size: 14, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gap) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(Array(grid.enumerated()), id: \.offset) { _, col in
                            VStack(spacing: gap) {
                                ForEach(Array(col.enumerated()), id: \.offset) { _, day in
                                    let key = Self.dayFormatter.string(from: day)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color(level(totalByDay[key] ?? 0)))
                                        .frame(width: cell, height: cell)
                                        .help("\(key): \(formatTokens(totalByDay[key] ?? 0))")
                                }
                            }
                        }
                    }
                    monthLabels
                }
            }
        }
        .padding(16)
        .background(Color(hex: 0xFAFAFA))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xEEEEEE)))
    }

    // 月份标签：每列首日是月初则标月份
    private var monthLabels: some View {
        HStack(spacing: gap) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, col in
                let first = col.first!
                let cal = Calendar.current
                let dayNum = cal.component(.day, from: first)
                Text(dayNum <= 7 ? Self.monthFormatter.string(from: first) : "")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .frame(width: cell)
            }
        }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f
    }()
    static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M月"; f.timeZone = .current; return f
    }()
}

#Preview {
    let cal = Calendar.current
    var days: [HeatmapDay] = []
    for i in 0..<120 {
        let d = cal.date(byAdding: .day, value: -i, to: Date())!
        days.append(HeatmapDay(date: cal.startOfDay(for: d), total: Int.random(in: 0...100_000_000)))
    }
    return HeatmapView(days: days).padding().frame(width: 420)
}
```

- [ ] **Step 2: 编译 + Canvas 验证（网格 + 月份 + 颜色分档）**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 提交**

```bash
git add ccMonitor/Views/HeatmapView.swift
git commit -m "feat: 热力图视图(7×52网格+动态分档+月份标签)"
```

---

## Task 14: 设置面板（⑤）

**Files:**
- Create: `ccMonitor/Views/SettingsView.swift`

数据库路径 + 实时模型列表（每模型 4 个单价输入框）+ 刷新间隔。

- [ ] **Step 1: 写 SettingsView**

```swift
// ccMonitor/Views/SettingsView.swift
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

            // 数据库路径
            VStack(alignment: .leading, spacing: 4) {
                Text("数据库路径").font(.system(size: 12, weight: .medium))
                HStack {
                    TextField("路径", text: $settings.dbPath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { pickDBFile() }
                }
            }

            // 刷新间隔
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

            // 模型价格列表
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
        var p = pricing.pricing(for: model)
        return VStack(alignment: .leading, spacing: 4) {
            Text(model).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                priceField("输入", get: { p.input }, set: { p.input = $0; pricing.setPricing(p, for: model) })
                priceField("输出", get: { p.output }, set: { p.output = $0; pricing.setPricing(p, for: model) })
                priceField("缓存读", get: { p.cacheRead }, set: { p.cacheRead = $0; pricing.setPricing(p, for: model) })
                priceField("缓存写", get: { p.cacheCreate }, set: { p.cacheCreate = $0; pricing.setPricing(p, for: model) })
            }
        }
        .padding(8)
        .background(Color(hex: 0xFAFAFA))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func priceField(_ label: String, get: @escaping () -> Double, set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            TextField("0", value: Binding(get: get, set: set), format: .number)
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
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 提交**

```bash
git add ccMonitor/Views/SettingsView.swift
git commit -m "feat: 设置面板(db路径/模型单价/刷新间隔)"
```

---

## Task 15: 主面板容器 DashboardView

**Files:**
- Create: `ccMonitor/Views/DashboardView.swift`

组合标题栏 + 滚动内容（模型列表 → 汇总 → 折线图 → 热力图）+ 设置 sheet + 自定义日期 sheet。

- [ ] **Step 1: 写 DashboardView**

```swift
// ccMonitor/Views/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: DataStore
    @State private var showSettings = false
    @State private var showDatePicker = false
    @State private var customStart = Date()
    @State private var customEnd = Date()

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
                    HeatmapView(days: store.heatmap)
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
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: Xcode Canvas 确认完整面板布局**

- [ ] **Step 4: 提交**

```bash
git add ccMonitor/Views/DashboardView.swift
git commit -m "feat: 主面板容器(标题栏+滚动内容+设置/日期sheet)"
```

---

## Task 16: AppDelegate 菜单栏组装 + 入口

**Files:**
- Modify: `ccMonitor/ccMonitorApp.swift`
- Create: `ccMonitor/AppDelegate.swift`

NSStatusItem（仅图标）点击切换 NSPopover；popover 承载 DashboardView。

- [ ] **Step 1: 写 AppDelegate**

```swift
// ccMonitor/AppDelegate.swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var store: DataStore!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let pricing = PricingStore()
        store = DataStore(settings: settings, pricing: pricing)

        // 菜单栏图标（仅图标）
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "用量")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Popover 承载 SwiftUI 面板
        popover = NSPopover()
        popover.behavior = .transient   // 点击外部自动关闭
        popover.contentSize = NSSize(width: 420, height: 640)
        popover.contentViewController = NSHostingController(rootView: DashboardView(store: store))

        store.startTimer()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
```

- [ ] **Step 2: 改写入口绑定 AppDelegate**

```swift
// ccMonitor/ccMonitorApp.swift
import SwiftUI

@main
struct ccMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏 app 无主窗口；用 Settings 占位避免空 Scene
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' build`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 运行 app，手动验收**

Run: `xcodebuild -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS' -derivedDataPath ./build build && open ./build/Build/Products/Debug/ccMonitor.app`

验收清单：
- 菜单栏出现图标，Dock 无图标。
- 点击图标弹出面板，显示真实模型数据。
- 切换时间范围按钮，汇总区数字变化。
- 折线图多色线、热力图网格、月份标签正常。
- 点设置→显示模型列表→填单价→完成后成本更新。
- 点击面板外部自动关闭。

- [ ] **Step 5: 提交**

```bash
git add ccMonitor/AppDelegate.swift ccMonitor/ccMonitorApp.swift
git commit -m "feat: 菜单栏组装(NSStatusItem+NSPopover)与入口"
```

---

## Task 17: 构建脚本与 README

**Files:**
- Create: `build.sh`
- Create: `README.md`

- [ ] **Step 1: 写 build.sh**

```bash
#!/usr/bin/env bash
# 构建 ccMonitor.app 到 ./build 目录
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="ccMonitor"
PROJECT="ccMonitor.xcodeproj"
CONFIG="${1:-Release}"

echo "==> 构建 $SCHEME ($CONFIG)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath ./build \
  build

APP="./build/Build/Products/$CONFIG/ccMonitor.app"
echo "==> 完成: $APP"
echo "运行: open \"$APP\""
```

- [ ] **Step 2: 写 README.md**

```markdown
# cc-switch monitor

macOS 菜单栏应用，从 `~/.cc-switch/cc-switch.db` 读取 token 用量并可视化。

## 功能
- 按模型展示本月用量、缓存率、成本（成本用自设单价重算）
- 进度条显示「今日 / 本月」token
- 时间范围（当日/7天/30天/自定义）汇总统计
- 最近30天用量折线图（多模型，悬停查看）
- 7×52 Token 活动热力图
- 设置：数据库路径、模型单价、刷新间隔

## 构建与运行
```bash
# 首次需同意 Xcode license
sudo xcodebuild -license accept

# 构建
./build.sh            # Release
./build.sh Debug      # Debug

# 运行
open ./build/Build/Products/Release/ccMonitor.app
```

## 在 Xcode 中开发/预览
1. 打开 `ccMonitor.xcodeproj`
2. 选中任意 View 文件，按 ⌥⌘↩ 打开 Canvas 实时预览
3. ⌘R 运行；菜单栏出现图标，点击弹出面板

## 测试
```bash
xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS'
```

## 说明
- 应用以**只读**方式访问 cc-switch.db，不写入。
- 单价与设置存于 app 自己的 UserDefaults。
- 数据源全部来自本地 session 日志，无供应商分组。
```

- [ ] **Step 3: 赋可执行权限并验证**

Run: `chmod +x build.sh && ./build.sh Debug`
Expected: `BUILD SUCCEEDED` 且输出 .app 路径。

- [ ] **Step 4: 提交**

```bash
git add build.sh README.md
git commit -m "docs: 构建脚本与 README"
```

---

## Task 18: 全量测试 + 最终验收

- [ ] **Step 1: 跑全部单测**

Run: `xcodebuild test -project ccMonitor.xcodeproj -scheme ccMonitor -destination 'platform=macOS'`
Expected: 所有测试 PASS（Formatters / Pricing / DateWindows / UsageRepository）。

- [ ] **Step 2: 对照 spec 逐项验收**

- [ ] 菜单栏仅图标，点击弹面板
- [ ] 模型列表按本月用量降序，进度条「今日/本月」+ 黑色文字
- [ ] 缓存率 = cache_read/(input+cache_read)
- [ ] 成本用自设单价（$/1M）重算
- [ ] 汇总区跟随时间范围，含缓存率进度条
- [ ] 折线图固定30天多模型 + 悬停
- [ ] 热力图 7×52 + 月份标签
- [ ] 设置：db路径 / 实时模型列表+单价 / 刷新间隔
- [ ] 只读访问，未写 cc-switch.db

- [ ] **Step 3: 最终提交**

```bash
git add -A
git commit -m "test: 全量测试通过，完成 cc-switch monitor"
```
