## Why

Dashboard 现在能显示汇总和当天 hourly overview，但缺少按日期观察长期使用节奏的视图。增加 GitHub-style calendar heatmap 可以让用户快速发现高消耗日期、空白日期和近期趋势，并在 hover 时直接查看当天 cost 与 token 消耗。

## What Changes

- 在 Dashboard 页面增加一个日期热力图，用日历网格展示每日 usage 强度，视觉风格参考 GitHub contribution graph。
- 每个日期单元格按当天 cost 或 token 消耗映射到离散色阶，零用量日期保持低强调的空状态。
- 鼠标 hover 日期单元格时展示 tooltip，包含本地日期、当天 cost、total tokens、input/output tokens，以及 request count。
- 热力图使用现有本地 `token_usages` 数据聚合，不保存 prompt、response、tool output、Authorization 或 API key。
- 保留现有 Dashboard summary、hourly overview 图表、source/provider/model/y-axis 过滤控件和时间范围语义。
- Non-goals: CLI tools, network capture, prompt saving, cloud sync, Windows/Linux。

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `menu-bar-ui`: Dashboard 页面必须展示日期 usage heatmap，并在 hover 日期时展示当天 cost 和 token 统计 tooltip。

## Impact

- Affected UI/state: Dashboard SwiftUI layout, heatmap view model, hover/tooltip presentation, empty/loading state handling.
- Affected data access: `TokenUsagesRepository` needs a daily aggregation query over `token_usages`.
- Affected tests: repository daily aggregation tests, heatmap data/color bucketing tests, Dashboard page composition tests.
- No database schema migration is expected; daily values are derived from existing event rows.
