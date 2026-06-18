# Fix Report - gpt-5.5 今日用量偏高

## Bug 描述
软件中 `gpt-5.5` 今日用量约 63M，但官方口径约 34M。

## 根因
不同 app_type 的 `input_tokens` 语义不一致。cc-switch 官方源码中将 `codex` 和 `gemini` 作为 cache-inclusive app type：这两类记录的 `input_tokens` 已包含缓存读命中的 token，聚合时需要先扣除 `cache_read_tokens` 得到未命中输入；其它 app type 默认为 Claude/Anthropic 风格，`input_tokens` 已是未命中输入。真实库验证时，`gpt-5.5` 的旧四字段总量明显偏高，而 `deepseek-v4-pro` 需要把 `cache_read_tokens` 加回总量才反映真实用量。

## 尝试记录
- 直接查询今日 `gpt-5.5` 四类 token：确认 `input + output` 接近官方数值，旧总量明显偏大。
- 检查 `request_id` 与用量行去重：记录数与 distinct 数一致，排除重复写入。
- 检查 `request_model` / `pricing_model` / `data_source`：模型映射正常，问题集中在缓存字段口径。
- 验证 `input_tokens > cache_read_tokens` 启发式：真实库中 `deepseek-v4-pro` 存在 `input_tokens > cache_read_tokens` 但 input 仍不包含缓存读的记录，因此不能用大小关系统一判断字段语义。
- 抽样验证 `proxy + gpt-*`：`claude-desktop` 路径的 `input_cost_usd` 按原始 `input_tokens` 计费，说明即使计费模型是 GPT，也不能据此判断 input 已含缓存；`app_type=codex` 路径才按 `input_tokens - cache_read_tokens` 计费。
- 对照 cc-switch 官方源码：`services/sql_helpers.rs`、`proxy/usage/calculator.rs` 和前端 `types/usage.ts` 都使用 `app_type IN ('codex', 'gemini')` 作为唯一 cache-inclusive 白名单。

## 最终方案
在 `UsageRepository` 中集中定义展示总量 SQL，并与 cc-switch 官方规则保持一致：当 `app_type IN ('codex', 'gemini') AND input_tokens >= cache_read_tokens` 时，用 `input_tokens - cache_read_tokens` 作为未命中输入；其它记录直接使用 `input_tokens`。总量统一计为 `未命中输入 + output_tokens + cache_read_tokens + cache_creation_tokens`。模型列表、汇总、趋势、热力图和菜单栏今日总量都复用同一展示总量口径。缓存率使用 `cache_read / (未命中输入 + cache_creation + cache_read)`，成本仍按四类单价独立重算。

## 经验教训
缓存 token 字段在不同数据源中的含义不完全一致。以后新增总量类指标时，应优先确认字段是否是互斥类别，不能默认四类 token 可直接相加，也不能默认所有模型都排除缓存字段。

# Fix Report - 主题切换只影响设置页且背景不变

## Bug 描述
新增外观切换后，主面板一直保持浅色；设置页部分控件会切换，但页面背景仍是白色。

## 根因
主题切换只设置了 `NSApp.appearance`，没有显式驱动 SwiftUI 根视图的 `colorScheme`，popover 内容不会稳定重算。同时 `UB.Canvas.canvasBackground` 使用固定浅灰 `Color(red:)`，在深色外观下仍保持浅色；设置页和主面板都复用了这个固定背景。

## 尝试记录
- 检查标题按钮状态和设置页选择器：状态能持久化，排除设置未生效。
- 检查颜色 token：发现根背景是固定 RGB，确认背景不跟随系统外观。
- 检查 AppKit/SwiftUI 边界：popover 和设置窗口是 `NSHostingController`，需要同时同步 AppKit appearance 与 SwiftUI `preferredColorScheme`。

## 最终方案
将根背景改为系统语义色 `controlBackgroundColor`；为 Dashboard、Settings、Snapshot 根视图添加 `preferredColorScheme`，并用 appearance mode 触发视图刷新；AppDelegate 在模式变化时同步更新 `NSApp`、popover 内容视图、popover 窗口和设置窗口的 appearance。

## 经验教训
macOS SwiftUI 菜单栏应用不能只依赖 `NSApp.appearance`。跨 `NSPopover`、`NSWindow` 和 `NSHostingController` 的主题状态应同时使用语义颜色 token、SwiftUI colorScheme 和 AppKit appearance。

## 追加修复
“深色 -> 跟随系统”时，如果系统当前是浅色，界面仍可能保持深色，因为 `system` 模式使用了 `nil` 让 AppKit/SwiftUI 继承外观，已有 popover/hosting view 会保留或延迟解析上一轮深色外观。最终改为把“跟随系统”实时解析成当前系统的明确浅/深色，并监听 `AppleInterfaceThemeChangedNotification` 更新系统外观状态；同时移除主题切换时的根视图 `.id(...)` 强制重建，减少切换卡顿。
