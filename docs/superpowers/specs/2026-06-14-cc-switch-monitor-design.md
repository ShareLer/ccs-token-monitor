# cc-switch monitor 设计文档

> macOS 菜单栏应用，从 cc-switch 数据库读取 token 用量并可视化展示。
> 日期：2026-06-14

## 0. 背景与关键数据事实

数据源：`~/.cc-switch/cc-switch.db`，核心表 `proxy_request_logs`（实测 9217 行）。

经实测确认的关键事实（决定了本设计的取舍）：

1. **`created_at` 是秒级 Unix 时间戳**。所有时间过滤用 `datetime(created_at,'unixepoch','localtime')` 转本地时区。
2. **四类 token 字段**：`input_tokens` / `output_tokens` / `cache_read_tokens` / `cache_creation_tokens`（均 INTEGER）。
3. **成本字段不可信**：db 中虽有 `*_cost_usd`，但用户要求**完全用自己设置的单价重算**，不读取 db 成本。
4. **拿不到供应商**：`providers` 表有 5 个供应商（Bailian/DeepSeek/DCC/Dasu-claude/Dasu-gpt），但 logs 表 9217 条记录 `provider_id` 全是 `_session`、`data_source` 全是 `session_log`（用量来自本地 Claude Code session 日志解析，不走代理）。**因此不做供应商分组层，直接按 model 展示。**
5. 真实出现的 model：`claude-sonnet-4-6`、`deepseek-v4-pro`、`deepseek-v4-flash`、`claude-opus-4-7`、`claude-opus-4-6`、`glm-5-external`、`zai/GLM-5`、`auto`、`auto-max`。

## 1. 产品决策汇总（已与用户逐项确认）

| 决策点 | 结论 |
|--------|------|
| 技术栈 | SwiftUI + AppKit（NSStatusItem + NSPopover），纯原生 |
| 菜单栏 | 仅图标，点击弹出 popover 面板 |
| 供应商层 | **不做**，按模型逐个展示 |
| 模型列表排序 | 按本月用量降序 |
| 模型进度条 | 分子=今日该模型 token，分母=本月该模型 token |
| 汇总统计区 | 跟随顶部时间按钮，不分模型，显示总量 |
| 价格 | 每模型 4 类单价（输入/输出/缓存读/缓存写），默认全 0，用户手动填，存 UserDefaults |
| 成本公式 | 用用户单价重算，不读 db 成本字段 |
| 缓存率公式 | `cache_read / (input + cache_read)` |
| 折线图 | 固定最近 30 天，按天聚合，每模型一条线 |
| 热力图 | 7×52 网格，按日总 token 量分 5 档着色 |
| 刷新 | 默认每 5 分钟，间隔可在设置中调（5/10/15/30 分钟），也可手动刷新 |
| db 访问 | 只读打开（`SQLITE_OPEN_READONLY`），绝不写 cc-switch.db |

## 2. 整体架构

LSUIElement 菜单栏 app（无 Dock 图标）。

```
App 入口 (ccMonitorApp, @main)
  └─ AppDelegate: 创建 NSStatusItem(仅图标)
       └─ 点击 → NSPopover 弹出 SwiftUI DashboardView

DataStore (ObservableObject, 状态中枢)
  ├─ @Published: modelUsages / summary / trendPoints / heatmapDays / loadError
  ├─ Timer 定时刷新(间隔来自 SettingsStore)
  ├─ selectedTimeRange (顶部按钮状态) → 变化时只重查 summary
  └─ 调用 UsageRepository 执行查询

UsageRepository (数据访问层)
  └─ 用 SQLite C API 只读打开 db，执行聚合 SQL，返回 Swift 结构体

PricingStore (UserDefaults): [模型名 → ModelPricing(4类单价)]
SettingsStore (UserDefaults): dbPath / refreshIntervalMinutes
```

**只读原则**：以 `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` 打开，设 `busy_timeout`，避免与 cc-switch 写入冲突。所有 app 配置存自己的 UserDefaults，不碰 cc-switch.db。

## 3. 文件结构与模块职责

```
ccMonitor/
├── ccMonitorApp.swift          // @main 入口，绑定 AppDelegate
├── AppDelegate.swift           // NSStatusItem + NSPopover 生命周期
├── Models/
│   ├── UsageModels.swift       // ModelUsage / SummaryStats / TrendPoint / HeatmapDay / TimeRange
│   └── Pricing.swift           // ModelPricing(4类单价)
├── Data/
│   ├── SQLiteDatabase.swift    // SQLite C API 薄封装(只读 open/prepare/step/finalize)
│   └── UsageRepository.swift   // 所有聚合查询 + 时间窗计算
├── Stores/
│   ├── DataStore.swift         // ObservableObject 状态中枢 + 定时器
│   ├── PricingStore.swift      // 价格持久化(UserDefaults, Codable)
│   └── SettingsStore.swift     // dbPath / refreshInterval(UserDefaults)
├── Views/
│   ├── DashboardView.swift     // 主面板容器(420px 宽，对应整个 ref.html)
│   ├── ModelListView.swift     // ① 模型列表 + 进度条
│   ├── SummaryView.swift       // ② 时间范围按钮 + 汇总统计 + 缓存率进度条
│   ├── TrendChartView.swift    // ③ 折线图(Swift Charts)
│   ├── HeatmapView.swift       // ④ 热力图
│   ├── SettingsView.swift      // ⑤ 设置面板(单独窗口或 sheet)
│   └── Components/
│       ├── UsageProgressBar.swift   // 圆角进度条 + 黑色叠加文字
│       ├── TimeRangeSelector.swift  // 时间范围按钮组
│       └── DatePickerSheet.swift    // 自定义日期范围弹窗
└── Resources/
    ├── Assets.xcassets
    └── Info.plist              // LSUIElement=YES
```

每个 View 只依赖 `DataStore` 暴露的数据，职责单一，可用 SwiftUI `#Preview` + mock 数据独立预览。

## 4. 数据模型（Swift 结构体）

```swift
struct ModelUsage: Identifiable {
    var id: String { model }
    let model: String
    // 本月口径
    let monthInput, monthOutput, monthCacheRead, monthCacheCreate: Int
    // 今日口径
    let todayTotal: Int
    var monthTotal: Int { monthInput + monthOutput + monthCacheRead + monthCacheCreate }
    var cacheRate: Double {        // cache_read / (input + cache_read)
        let denom = monthInput + monthCacheRead
        return denom == 0 ? 0 : Double(monthCacheRead) / Double(denom)
    }
    func cost(with p: ModelPricing) -> Double {  // 用单价重算，单价单位 $/1M
        (Double(monthInput) * p.input + Double(monthOutput) * p.output
         + Double(monthCacheRead) * p.cacheRead + Double(monthCacheCreate) * p.cacheCreate) / 1_000_000
    }
}

struct SummaryStats {          // ② 汇总区，跟随时间范围
    let input, output, cacheRead, cacheCreate: Int
    var total: Int { input + output + cacheRead + cacheCreate }
    var cacheRate: Double { let d = input + cacheRead; return d == 0 ? 0 : Double(cacheRead)/Double(d) }
}

struct TrendPoint {            // ③ 折线图一个点
    let day: String            // yyyy-MM-dd
    let model: String
    let total: Int
}

struct HeatmapDay {            // ④ 热力图一格
    let date: Date
    let total: Int
    // level(0-4) 在 View 层按全局 max 动态分档
}

struct ModelPricing: Codable {   // 单价 $/1M token，默认全 0
    var input, output, cacheRead, cacheCreate: Double
}

enum TimeRange { case today, last7d, last30d, custom(Date, Date) }
```

## 5. 三套独立时间语义（最易错处）

| 模块 | 时间窗 | 受顶部时间按钮影响 |
|------|--------|------------------|
| ① 模型列表进度条 | 固定：今日 token / 本月 token | ❌ |
| ② 汇总统计区 | 跟随按钮（今日/7天/30天/自定义） | ✅ |
| ③ 折线图 | 固定：最近 30 天，按天聚合 | ❌ |
| ④ 热力图 | 固定：最近 52 周（7×52） | ❌ |

顶部时间按钮切换 → 只触发 ② 的重新查询，其余三模块用缓存数据。

## 6. SQL 查询定义

所有查询基于 `created_at`（秒级），时间窗端点用 Swift 计算后以参数 `:start` / `:end` 传入。

**① 模型列表**（本月窗 + 今日窗 各查一次，按 model 聚合，本月结果决定排序）：
```sql
SELECT model,
       SUM(input_tokens), SUM(output_tokens),
       SUM(cache_read_tokens), SUM(cache_creation_tokens)
FROM proxy_request_logs
WHERE created_at >= :start AND created_at < :end
GROUP BY model;
```
本月查询结果按 `(四类之和) DESC` 排序；今日查询结果做成 `[model: todayTotal]` 字典合并进 ModelUsage。

**② 汇总统计**（跟随时间范围，不分模型）：
```sql
SELECT SUM(input_tokens), SUM(output_tokens),
       SUM(cache_read_tokens), SUM(cache_creation_tokens)
FROM proxy_request_logs
WHERE created_at >= :start AND created_at < :end;
```

**③ 折线图**（最近 30 天，按天 × 模型聚合）：
```sql
SELECT date(created_at,'unixepoch','localtime') AS day, model,
       SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens)
FROM proxy_request_logs
WHERE created_at >= :start_30d
GROUP BY day, model ORDER BY day;
```

**④ 热力图**（最近 52 周，按天聚合）：
```sql
SELECT date(created_at,'unixepoch','localtime') AS day,
       SUM(input_tokens+output_tokens+cache_read_tokens+cache_creation_tokens)
FROM proxy_request_logs
WHERE created_at >= :start_52w
GROUP BY day;
```

## 7. 视觉规格（对照 ref.html）

- 容器宽 420px，圆角 12px，阴影，白底。
- 顶部标题栏：标题「Token 使用量监控」+ 刷新按钮 + 设置按钮 +（popover 内可省略关闭按钮，点击外部自动关闭）。
- 模型列表：每行 model 名 + 缓存率（琥珀色 #FFC107）+ 成本（绿色 #4CAF50）+ 进度条。
- 进度条：高 14px，圆角，蓝色渐变 `#2196F3→#21CBF3` 填充；**叠加黑色加粗文字** `今日 / 本月`（黑色确保任意背景对比度，这是硬性要求）。
- 汇总区：浅蓝底 #f0f8ff；大字总 token（28px 蓝色）+ 输入/输出/缓存三列 + 缓存率进度条（琥珀渐变，黑色文字）。
- 折线图：Swift Charts，多模型多色线，悬停 tooltip 显示该天全部模型名+值。
- 热力图：7 行 × 52 列圆角方块，无活动=灰 #e0e0e0，4 档绿；底部标月份。
- 数字格式化：≥1M 显示 `1.2M`，≥1K 显示 `12.5K`，成本显示 `$74.74`。

## 8. 错误处理（仅必要）

- db 文件不存在 → 面板显示「未找到数据库，请在设置中指定路径」，提供选择路径入口。
- db 被锁 → 只读 + `busy_timeout` 重试；仍失败则保留上次数据 + 顶部提示「读取失败」。
- 表/字段缺失或 SQL 异常 → 该查询返回空，不崩溃。
- 价格未设置（默认 0）→ 成本显示 `$0.00`，不报错。

## 9. 设置面板

- **数据库路径**：文本框 + 「选择文件」按钮，默认 `~/.cc-switch/cc-switch.db`。
- **模型列表**：实时从 db 查 `SELECT DISTINCT model FROM proxy_request_logs`，列出每个有历史数据的模型，每个模型下 4 个单价输入框（输入/输出/缓存读/缓存写，$/1M）。
- **刷新间隔**：下拉选 5/10/15/30 分钟。
- 所有改动存 UserDefaults，保存后触发 DataStore 重新刷新。

## 10. 测试策略（TDD，聚焦数据层）

- `UsageRepository` 单测：代码创建临时 SQLite，插入已知行，断言聚合结果。重点覆盖：
  - 今日/本月时间窗的起止边界（本地时区）。
  - 缓存率公式 `cache_read/(input+cache_read)`，含分母为 0 的情况。
  - 成本重算公式（单价 $/1M），含单价为 0。
  - 按天聚合的日期分组正确性。
- 时间窗计算单测：「今日 00:00」「本月 1 号」「30 天前」「52 周前」在本地时区下的 Unix 秒值。
- View 层不写单测，用 SwiftUI Preview + mock 数据目视验证。

## 11. 构建与预览（Xcode）

- 提供完整 Xcode 项目（`.xcodeproj` 或 SPM `Package.swift` + 可在 Xcode 打开）。
- 每个 View 带 `#Preview`，注入 mock DataStore，可在 Xcode Canvas 实时预览。
- 提供构建脚本（`xcodebuild` 命令）生成 `.app`。
- 最低 macOS 版本：13.0（Swift Charts 需要 macOS 13+）。

## 12. 范围边界（YAGNI）

明确**不做**：
- 供应商分组（数据拿不到）。
- 写回 cc-switch.db。
- 实时文件监听（用定时刷新足够）。
- 多 app_type（数据全是 claude）。
- 配额/预算告警（无配额概念）。
