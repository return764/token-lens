## 1. Daily Aggregation Model And Repository

- [x] 1.1 Add `DailyUsageBucket` and heatmap data helpers in `Sources/TokenLensApp/Models/OverviewModels.swift` or a nearby model file.
- [x] 1.2 Add `TokenUsagesRepository.fetchDailyAggregated(since:before:)` in `Sources/TokenLensApp/Database/TokenUsagesRepository.swift`, aggregating input/output/cached/cache write/reasoning/total tokens, cost, and request count by local date.
- [x] 1.3 Add repository tests in `Tests/TokenLensTests/TokenUsagesRepositoryTests.swift` for same-day grouping, cross-source/provider/model totals, inclusive start, exclusive end, and local-day boundary behavior.

## 2. App State Refresh

- [x] 2.1 Add published heatmap state and trailing-53-week bounds to `Sources/TokenLensApp/App/AppState.swift`.
- [x] 2.2 Refresh heatmap buckets from `AppState.refresh()` and live import refresh paths without tying the heatmap range to `timeRange`.
- [x] 2.3 Add `AppState` tests in `Tests/TokenLensTests/AppStateTests.swift` verifying heatmap data refreshes independently from Today/This Month/All summary ranges.

## 3. Heatmap View

- [x] 3.1 Create `Sources/TokenLensApp/Components/DailyUsageHeatmapView.swift` with fixed-size weekday/week grid cells, month labels, weekday reference labels, zero-usage cells, and a compact legend.
- [x] 3.2 Implement hover selection and tooltip in `DailyUsageHeatmapView`, showing local date, cost, total tokens, input tokens, output tokens, and request count.
- [x] 3.3 Add data/color bucketing tests in `Tests/TokenLensTests/DailyUsageHeatmapDataTests.swift` covering cost-based levels, token fallback when all costs are zero, zero days, sorting, and 53-week grid generation.

## 4. Dashboard Integration

- [x] 4.1 Insert the heatmap into `Sources/TokenLensApp/Settings/SettingsTab.swift` between dashboard summary and overview content.
- [x] 4.2 Preserve existing Dashboard summary, hourly overview chart, overview filters, and tab navigation behavior.
- [x] 4.3 Update `Tests/TokenLensTests/DashboardPageTests.swift` for any new Dashboard page composition or view model expectations.

## 5. Verification

- [x] 5.1 Run targeted tests for repository, app state, heatmap data, overview chart data, and Dashboard page behavior.
- [x] 5.2 Run the full Swift test suite with `swift test`.
- [x] 5.3 Manually launch the app or a preview build and verify the heatmap fits the minimum Dashboard window width and tooltip positioning is clamped.
