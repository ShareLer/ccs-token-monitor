# Fix Report - gpt-5.5 今日用量偏高

## Bug 描述
软件中 `gpt-5.5` 今日用量约 63M，但官方口径约 34M。

## 根因
不同模型/数据源的 `input_tokens` 语义不一致。Codex session 或计费模型为 `gpt-*` 时，`input_tokens` 已包含缓存读命中的 token，因此再加 `cache_read_tokens` 会重复计入；但 DeepSeek 等 session_log 模型的 `input_tokens` 不包含 `cache_read_tokens`，总量需要把缓存读单独加回。真实库验证时，`gpt-5.5` 的 `input + output` 接近官方数值，而 `deepseek-v4-pro` 需要 `input + output + cache_read` 才反映真实总量。

## 尝试记录
- 直接查询今日 `gpt-5.5` 四类 token：确认 `input + output` 接近官方数值，旧总量明显偏大。
- 检查 `request_id` 与用量行去重：记录数与 distinct 数一致，排除重复写入。
- 检查 `request_model` / `pricing_model` / `data_source`：模型映射正常，问题集中在缓存字段口径。

## 最终方案
在 `UsageRepository` 中集中定义展示总量 SQL：对 `codex_session` 或计费模型为 `gpt-*` 的记录，总量只计 `input_tokens + output_tokens`；其它模型计 `input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens`。计费模型优先使用 `pricing_model`，为空时回退 `model`。模型列表、汇总、趋势、热力图和菜单栏今日总量都复用同一展示总量口径。缓存率继续使用 `cache_read / (input + cache_read)`，成本仍按四类单价独立重算。

## 经验教训
缓存 token 字段在不同数据源中的含义不完全一致。以后新增总量类指标时，应优先确认字段是否是互斥类别，不能默认四类 token 可直接相加，也不能默认所有模型都排除缓存字段。
