## Context

Dashboard overview 当前依赖 `TokenUsagesRepository.fetchMinuteAggregated` 查询分钟桶，`AppState` 用最近 24 小时作为 overview 查询下限，并允许最多 1440 个 bucket。`OverviewChartView`、`OverviewChartData`、tooltip 和测试也围绕 `MinuteAggregation.minute` 命名。

本次需求把 overview 从短窗口分钟粒度改为当天小时粒度。数据仍来自 `token_usages`，不引入 `daily_usage` 或新的预聚合表，也不改变本地 JSONL 扫描、去重、计价和隐私边界。

## Goals / Non-Goals

**Goals:**

- Dashboard overview 图表展示当前本地日历日的 24 个小时范围。
- 聚合查询按小时分桶，同一小时内的 usage 合并为一个 bucket。
- source/provider/model/y-axis 过滤继续作用于 hourly overview。
- tooltip、坐标轴、hover hit-testing 和测试使用小时粒度语义。
- 菜单栏和 Dashboard 顶部汇总继续遵守用户选择的 Today / This Month / All 时间范围。

**Non-Goals:**

- 不新增数据库表、迁移或后台预聚合任务。
- 不改变 `token_usages` 写入、扫描 adapter 或 event-level dedup 行为。
- 不新增跨天/周/月的 overview 粒度选择器。
- 不改变 Recent Usage 列表和 Local Sources 状态页。

## Decisions

1. Use local start/end of today as the overview window.

   `AppState` should compute `overviewStartDate` as `Calendar.current.startOfDay(for: Date())` and also pass an exclusive end date for tomorrow's local start. This makes "today" match the app's local macOS user context, while repository filtering continues to compare ISO timestamps stored in SQLite.

   Alternative considered: keep a rolling 24-hour window. Rejected because the user asked for "当天" and hourly buckets should align to clock hours, not an arbitrary now-minus-24-hours boundary.

2. Replace minute-specific aggregation with hour-specific aggregation.

   Add or rename repository API to fetch hourly overview buckets using SQLite `strftime('%Y-%m-%dT%H:00:00Z', created_at)` and `GROUP BY hour`. Keep the selected source/provider/model filters and add an optional `before`/end date filter so records after today are excluded.

   Alternative considered: fetch raw usage and aggregate in Swift. Rejected because SQL aggregation is already the local pattern and avoids loading unnecessary rows into UI state.

3. Rename overview bucket domain types away from minute semantics.

   Change `MinuteAggregation.minute` style naming to hour/bucket naming where practical: e.g. `OverviewBucket.hour`, `fetchHourlyAggregated`, `hourAggregationFromRow`, chart x-values with `.hour`. This reduces the risk of future changes accidentally treating an hourly bucket as a minute.

   Alternative considered: keep the old names and only alter SQL. Rejected because it would make tests and chart code misleading.

4. Keep overview independent from the global menu time range.

   The existing `timeRange` setting should continue driving menu bar totals, menu usage groups, Recent Usage, and Dashboard summary metrics. The overview chart should consistently show today's hourly breakdown, so changing `timeRange` does not make overview switch to month/all-time.

   Alternative considered: make hourly overview follow every selected time range. Rejected because monthly/all-time hourly charts would be dense and outside the requested change.

## Risks / Trade-offs

- [Risk] SQLite `strftime` operates on stored UTC text while "today" is computed in local time. → Mitigation: convert local start/end Date values through the existing ISO8601 formatter and use those boundaries consistently.
- [Risk] Records exactly at tomorrow's start could appear if only `since` is used. → Mitigation: add an exclusive `before` filter for overview aggregation and distinct filter queries.
- [Risk] Chart hover hit-testing might still use a 60-second distance. → Mitigation: update bucket interval to 3600 seconds and adjust related tests.
- [Risk] Type renaming may touch several UI/test files. → Mitigation: keep the change scoped to overview models, chart view, repository aggregation, AppState overview refresh, and tests.
