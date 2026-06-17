## 1. Repository Aggregation

- [x] 1.1 Add hourly overview aggregation tests in `Tests/TokenLensTests/TokenUsagesRepositoryTests.swift` covering same-hour grouping, token/cost/request totals, source/provider/model filters, and exclusive today end boundary.
- [x] 1.2 Replace or supplement `TokenUsagesRepository.fetchMinuteAggregated` in `Sources/TokenLensApp/Database/TokenUsagesRepository.swift` with an hourly aggregation API that accepts `since` and `before` bounds.
- [x] 1.3 Update aggregation row mapping and overview bucket model names in `Sources/TokenLensApp/Models/OverviewModels.swift` so code no longer exposes minute-specific semantics for hourly data.

## 2. App State

- [x] 2.1 Update `Sources/TokenLensApp/App/AppState.swift` to compute overview bounds as local start-of-today through exclusive start-of-tomorrow.
- [x] 2.2 Update overview refresh and source/provider/model selection paths in `AppState` to call the hourly aggregation API with today bounds.
- [x] 2.3 Keep menu totals, Dashboard summary, and recent usage tied to the existing selected `timeRange`, while overview remains today's hourly breakdown.

## 3. Chart UI

- [x] 3.1 Update `Sources/TokenLensApp/Components/OverviewChartView.swift` to use hourly bucket intervals for x-values, visible domain length, hover maximum distance, rule marks, x-axis labels, and tooltip timestamps.
- [x] 3.2 Update `Sources/TokenLensApp/Settings/SettingsTab.swift` only where type or label changes are required by the overview bucket rename.

## 4. Tests and Validation

- [x] 4.1 Update `Tests/TokenLensTests/OverviewChartDataTests.swift` for hourly bucket naming and 24-bucket daily performance expectations.
- [x] 4.2 Add or update `AppState` overview tests to verify changing `timeRange` does not expand overview beyond today's hourly buckets.
- [x] 4.3 Run `swift test` and fix regressions.
- [x] 4.4 Run `openspec status --change "split-period-by-today-hour"` and confirm all required artifacts remain apply-ready.
