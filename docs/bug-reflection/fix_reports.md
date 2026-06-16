# Fix Report - gpt-5.5 今日用量偏高

## Bug 描述
软件中 `gpt-5.5` 今日用量约 63M，但官方口径约 34M。

## 根因
不同模型/数据源的 `input_tokens` 语义不一致。`data_source=session_log` 的 `input_tokens` 是未命中输入，不包含 `cache_read_tokens`；Codex 口径（`data_source=codex_session` 或 `app_type=codex`）的 `input_tokens` 已包含缓存读命中的 token，因此需要先扣除 `cache_read_tokens` 得到未命中输入。真实库验证时，`gpt-5.5` 的旧四字段总量明显偏高，而 `deepseek-v4-pro` 需要把 `cache_read_tokens` 加回总量才反映真实用量。

## 尝试记录
- 直接查询今日 `gpt-5.5` 四类 token：确认 `input + output` 接近官方数值，旧总量明显偏大。
- 检查 `request_id` 与用量行去重：记录数与 distinct 数一致，排除重复写入。
- 检查 `request_model` / `pricing_model` / `data_source`：模型映射正常，问题集中在缓存字段口径。
- 验证 `input_tokens > cache_read_tokens` 启发式：真实库中 `deepseek-v4-pro` 存在 `input_tokens > cache_read_tokens` 但 input 仍不包含缓存读的记录，因此不能用大小关系统一判断字段语义。
- 抽样验证 `proxy + gpt-*`：`claude-desktop` 路径的 `input_cost_usd` 按原始 `input_tokens` 计费，说明即使计费模型是 GPT，也不能据此判断 input 已含缓存；`app_type=codex` 路径才按 `input_tokens - cache_read_tokens` 计费。

## 最终方案
在 `UsageRepository` 中集中定义展示总量 SQL：`session_log` 一律直接使用 `input_tokens` 作为未命中输入；Codex 口径（`data_source=codex_session` 或 `app_type=codex`）用 `max(input_tokens - cache_read_tokens, 0)` 作为未命中输入；其它记录直接用 `input_tokens`。总量统一计为 `未命中输入 + output_tokens + cache_read_tokens + cache_creation_tokens`。模型列表、汇总、趋势、热力图和菜单栏今日总量都复用同一展示总量口径。缓存率使用 `cache_read / (未命中输入 + cache_read)`，成本仍按四类单价独立重算。

## 经验教训
缓存 token 字段在不同数据源中的含义不完全一致。以后新增总量类指标时，应优先确认字段是否是互斥类别，不能默认四类 token 可直接相加，也不能默认所有模型都排除缓存字段。
