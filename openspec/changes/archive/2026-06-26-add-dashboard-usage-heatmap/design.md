## Context

Dashboard 当前由 `SettingsTab` 作为主窗口内容，顶部展示 summary，下面展示当天 hourly overview 图表与过滤控件。`AppState` 负责刷新 usage 列表、菜单栏统计、local source 状态和 overview buckets；`TokenUsagesRepository` 已经通过 GRDB 查询 `token_usages` 并提供 hourly aggregation。

本次变更增加一个长期日期视图：类似 GitHub contribution graph 的 daily heatmap。数据仍来自本地 SQLite `token_usages`，不改变 LocalUsageAdapter、扫描服务、事件去重、计价或隐私边界。

## Goals / Non-Goals

**Goals:**

- 在 Dashboard 页面展示最近 53 周的 daily usage heatmap，包含今天。
- 按本地日期聚合 cost、total tokens、input/output/cached/cache write/reasoning tokens 和 request count。
- Hover 日期单元格时显示包含当天 cost 和 token 消耗的 tooltip。
- 在新 usage 导入或用户打开 Dashboard refresh 时更新 heatmap。
- 添加 repository、view-model/color bucket 和 Dashboard composition 测试。

**Non-Goals:**

- 不新增 `daily_usage` 预聚合表或数据库 migration。
- 不改变扫描 adapter、JSONL 解析、event-level dedup 或 cost calculation 行为。
- 不让 heatmap 存储或展示 prompt、response、tool output、Authorization、API key。
- 不新增 CLI tools、network capture、cloud sync、Windows/Linux 支持。
- 不把现有 hourly overview 图表改成 heatmap；两者在 Dashboard 中并存。

## Decisions

1. Use trailing 53 local-calendar weeks for the heatmap range.
   - Rationale: 53 周覆盖约一年并符合 GitHub contribution graph 的视觉模型，包含跨年边界和当前日期。
   - Alternative considered: follow the existing `timeRange` setting. Rejected because Today/This Month/All 会让日历网格形态频繁变化，且 All 可能过大。

2. Add a repository daily aggregation API instead of storing daily rows.
   - Add `DailyUsageBucket` to the app models and `TokenUsagesRepository.fetchDailyAggregated(since:before:)`.
   - Query `token_usages` grouped by local calendar day, bounded by inclusive `since` and exclusive `before`.
   - Rationale: the current schema is event-level and indexed by `created_at`; daily rows can be derived cheaply for 53 weeks without introducing migration or cache invalidation.
   - Alternative considered: create a `daily_usage` table. Rejected because the current app intentionally removed daily pre-aggregation and the requested feature does not require persistence.

3. Keep heatmap totals global across source/provider/model.
   - Rationale: Dashboard summary is already the global quick read, and the requested heatmap is a dashboard-level usage rhythm view. The existing source/provider/model filters remain scoped to the hourly overview chart.
   - Alternative considered: reuse overview filters for heatmap. Rejected because that would couple two different chart purposes and make the year view silently change when a user is tuning the hourly chart.

4. Build the heatmap as a dedicated SwiftUI grid component.
   - Create `DailyUsageHeatmapView` under `Sources/TokenLensApp/Components/`.
   - Use fixed-size square cells arranged by week columns and weekday rows, with stable dimensions and no layout shifts on hover.
   - Use SwiftUI hover state and a small material tooltip, following the existing `OverviewChartView` tooltip style where useful.
   - Rationale: the heatmap is a small discrete grid, so Swift Charts would add awkward axis/mark work for less control over GitHub-style layout.

5. Use daily cost as the primary intensity metric, with token fallback.
   - If any day has `costUsd > 0`, compute discrete levels from daily cost. If all costs are zero but tokens exist, compute levels from daily total tokens.
   - Rationale: the user explicitly cares about cost, but missing model prices can produce zero cost; token fallback prevents a fully blank-looking heatmap when real usage exists.

6. Refresh heatmap through `AppState`.
   - Add published `dailyUsageBuckets` and refresh them from `refresh()` and live import refresh paths.
   - Keep the heatmap range independent from `timeRange`, while summary/menu/recent usage keep using `timeRange`.
   - Rationale: this matches the existing ownership pattern and keeps Dashboard state centralized.

## Risks / Trade-offs

- [Risk] Local-date grouping can be wrong if SQLite UTC grouping is reused directly. -> Mitigation: compute bounds from `Calendar.current` and either group with a local-day helper that is tested across day boundaries or normalize rows into local day buckets after fetching bounded aggregates.
- [Risk] Dense 53-week grid may overflow the window width. -> Mitigation: use fixed small cells with horizontal scrolling or adaptive cell size, and test at the current 760 pt minimum width.
- [Risk] Tooltip can obscure nearby cells. -> Mitigation: position tooltip near the hovered cell but clamp within the heatmap container, mirroring the overview tooltip behavior.
- [Risk] All cost values may be zero for unknown models. -> Mitigation: use total tokens as the color intensity fallback while still showing `$0.0000` cost in tooltip.
- [Risk] Adding another Dashboard visualization can make the page crowded. -> Mitigation: place heatmap between summary and overview with compact heading/legend, not as a nested card.
