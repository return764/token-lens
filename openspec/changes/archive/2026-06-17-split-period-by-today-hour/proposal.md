## Why

当前 overview 图表按最近 1 小时、每 10 分钟拆分，能看到短时变化，但无法呈现当天完整的使用节奏。用户更需要一眼看到今天每个小时的 token/cost 分布，用来判断全天峰值、空档和来源差异。

## What Changes

- 将 Dashboard overview 图表的数据周期改为“当天”。
- 将 overview 图表的时间分桶改为“每小时”。
- 保留现有 source/provider/model/y-axis 过滤能力。
- 保留菜单栏和 Dashboard 选定时间范围的汇总展示语义；本次只改变 overview 图表的时间粒度与覆盖范围。
- 不新增预聚合表，仍基于 `token_usages` 即时查询和汇总。

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `menu-bar-ui`: Dashboard overview 图表必须按当天的小时桶展示，而不是最近 1 小时内的 10 分钟桶。

## Impact

- Affected UI/state: `AppState` overview 查询起止时间、图表 bucket 模型命名/显示、Dashboard overview rendering。
- Affected data access: `TokenUsagesRepository` overview 聚合查询需要支持小时级分桶。
- Affected tests: repository aggregation tests, overview chart data tests, and AppState overview refresh/filter tests.
- No database schema changes, no local source parsing changes, and no privacy model changes.
