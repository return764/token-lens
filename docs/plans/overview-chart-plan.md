# Overview Bar Chart Plan

> 日期：2026-06-14 | 状态：计划中

在 Settings 顶部新增 **Overview** 区块，提供按「分钟」聚合的 token 消耗柱状图，支持按 Source → Provider → Model 层层筛选。

---

## 1. 目标

- Settings 窗口顶部新增 **Overview Section**，独立于现有 "Recent Usage" / "Local Sources" / "Monitoring" 三段。
- 柱状图横轴为分钟级时间桶（如 `14:01`, `14:02`...），纵轴为 token 消耗量。
- 用户可筛选：**Source**（agentic_tool）→ **Provider**（provider_id）→ **Model**（model）。
- 同一分钟桶内 input / output / cached tokens 以**堆叠柱状图**呈现，颜色区分（上叠下，非并排）。
- 数据时间窗口限制在最近 24 小时内，并与 Settings 的 **Aggregation Range** 取交集：`Today` 从今天零点开始，`This Month` / `All` 也最多回看最近一天。
- 数据超窗口时可左右滚动（最多最近 24 小时，约 1440 个分钟桶）。
- Overview 区块高度固定；切换 `Tokens` / `Cost` 时 chart 和 legend 预留区域不发生高度跳变。
- 使用 Swift Charts 原生横向滚动；横向滚动 X 轴时，Y 轴刻度和标签固定在左侧。
- Y 轴范围和刻度交给 Swift Charts 自动计算，确保当前数据最大值可见。

---

## 2. 数据层

### 2.1 聚合查询 —— `TokenUsagesRepository`

新增方法签名：

```swift
/// 按分钟聚合 token 用量。source/provider/model 必传（不支持 All）。
/// 返回按分钟升序排列的聚合记录。
public func fetchMinuteAggregated(
    source: String,
    provider: String,
    model: String,
    since: Date? = nil,
    maxBuckets: Int = 1440
) throws -> [MinuteAggregation]
```

SQL 逻辑（GRDB raw SQL，WHERE 条件固定三个维度）：

```sql
SELECT
  strftime('%Y-%m-%dT%H:%M', created_at) AS minute,
  SUM(input_tokens)        AS total_input,
  SUM(output_tokens)       AS total_output,
  SUM(cached_input_tokens) AS total_cached_input,
  SUM(cache_write_tokens)  AS total_cache_write,
  SUM(reasoning_tokens)    AS total_reasoning,
  SUM(total_tokens)        AS total_all,
  SUM(cost_usd)           AS total_cost,
  COUNT(*)                AS request_count
FROM token_usages
WHERE agentic_tool = ?
  AND provider_id = ?
  AND model = ?
  AND created_at >= ?
GROUP BY minute
ORDER BY minute DESC
LIMIT ?
```

说明：
- 三个维度均必传 —— filter bar 无 `All` 选项，始终精确到某个 model。
- `since` 由 `AppState` 计算为 `max(timeRange.startDate, now - 24h)`；`LIMIT 1440` 对应最近一天的分钟桶上限。
- 索引 `idx_token_usages_created_at` 已覆盖该查询。

### 2.2 聚合模型 —— `MinuteAggregation`

```swift
/// 单个分钟桶的聚合数据
public struct MinuteAggregation: Identifiable, Equatable {
    public let minute: Date          // 分钟起点
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCachedInputTokens: Int
    public let totalCacheWriteTokens: Int
    public let totalReasoningTokens: Int
    public let totalTokens: Int
    public let totalCostUsd: Double
    public let requestCount: Int

    public var id: Date { minute }
}
```

存放位置：`Sources/TokenLensApp/Models/OverviewModels.swift`

#### 堆叠数据转换

`MinuteAggregation` 是宽表格式，chart 需要长表格式。在 `OverviewChartView` 内部做转换：

```swift
/// 一个分钟桶内的单条维度（供 Chart 堆叠）
struct BarSegment: Identifiable {
    let id: String        // "minute|dimension"
    let minute: Date
    let dimension: TokenDimension
    let count: Int
}

enum TokenDimension: String, Plottable {
    case input, output, cached
}
```

转换逻辑：每个 `MinuteAggregation` 产出 3 个 `BarSegment`（input/output/cached），共用同一个 `minute` x 值。Swift Charts 对同一 x 的多条 `BarMark` 自动堆叠。

### 2.3 筛选选项数据源 —— `TokenUsagesRepository`

新增三个轻量查询，供 Picker 渲染可选值。查询同样接受 `since`，保证 picker 选项和 chart 使用同一个 Aggregation Range / 最近一天窗口：

```swift
/// 获取当前时间窗口下出现过的 source 列表。
public func fetchDistinctSources(since: Date? = nil) throws -> [String]

/// 获取指定 source 下出现过的 provider_id 列表。
public func fetchDistinctProviders(for source: String, since: Date? = nil) throws -> [String]

/// 获取指定 source + provider 下出现过的 model 列表。
public func fetchDistinctModels(for source: String, provider: String, since: Date? = nil) throws -> [String]
```

SQL 示例：

```sql
SELECT DISTINCT provider_id FROM token_usages
  WHERE agentic_tool = ?
ORDER BY provider_id
```

---

## 3. UI 层

### 3.1 Overview Section 布局

```
┌─ Overview ────────────────────────────────────────────┐
│ [codex ▾] [openai ▾] [gpt-4o ▾]     [Tokens ▾]      │  ← filter bar
│                                                       │
│  ═╤══╤══╤══╤══╤══╤══╤══╤══╤══╤══╤══╤══╤══╤══╤══╤══  │  ← chart (bar chart)
│   ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  │
│   ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  ║  │
│  14:00  14:05  14:10  14:15  14:20  14:25  14:30...   │  ← x-axis time labels
│                                                       │
│  ███ Input    ███ Output    ███ Cached     │  ← legend
│  (堆叠顺序自下而上: Input → Output → Cached) │
└───────────────────────────────────────────────────────┘
```

### 3.2 Swift Charts 柱状图

使用 macOS 14 原生 **Swift Charts**（`import Charts`）渲染 `BarMark`。

关键点：
- **Y 轴模式**：Picker 切换 `Tokens`（input+output 堆叠）或 `Cost`。
- **堆叠柱状图**：同一分钟桶内多条数据（input / output / cached）共用同一个 `x` 值，Swift Charts 自动堆叠。用 `BarMark(x:y:stacking:)` 或直接对同一 x 投多条 `BarMark`，Charts 自动识别为堆叠。
- **颜色映射**：`inputTokens → blue`, `outputTokens → green`, `cachedInputTokens → orange`（`chartForegroundStyleScale`）。
- **排序**：确保数据按 input → output → cached 顺序排列，堆叠自下而上为 input、output、cached。
- **X 轴**：时间格式化（HH:mm）。使用 Swift Charts 原生 `chartScrollableAxes(.horizontal)` + `chartXVisibleDomain(length:)`，不再用外层 `ScrollView` 手写滚动。
- **Y 轴**：使用 `AxisMarks(position: .leading, values: .automatic(desiredCount: 4))`，不手写 y-scale domain 或 tick values，让 Swift Charts 根据当前数据自动决定范围和刻度；原生横向滚动会保持 Y 轴在左侧。
- **空状态**：无数据时显示 "No token usage for the selected filters."

### 3.3 Chart 最小宽度计算

```
chartWidth = max(minBars, barCount) * barWidth + padding
```

- `barWidth`: 12pt
- `barSpacing`: 8pt → 每列总宽 20pt
- `minBars`: 10（至少占满一半可见区域）
- `chartXVisibleDomain(length:)` 控制一次可见约 36 个分钟槽；数据不足时按实际槽位缩短，数据超过可见范围时原生横向滚动。
- Overview chart 固定高度为 320pt；legend 槽位固定高度约 18pt。`Cost` 模式隐藏 legend 但保留槽位，防止切换 Y 轴模式时 Overview section 高度跳变。

### 3.4 Filter 行为

三级联动 Picker，**无 All 选项** —— 始终精确选中一个 Source + Provider + Model 组合。

1. 选择 **Source** → 自动选中该 source 的第一个 provider（provider 列表刷新）→ 自动选中该 provider 的第一个 model（model 列表刷新）。
2. 选择 **Provider** → 自动选中该 provider 的第一个 model（model 列表刷新）。
3. 选择 **Model** → 直接重新查询。
4. 任一值变更 → 立即重新查询聚合数据并刷新图表。
5. Aggregation Range 变更 → `AppState.setTimeRange(_:)` 触发 `refresh()`，进而触发 `refreshOverview()`；overview 重新计算最近 24 小时上限内的可选项和聚合桶。

**初始化逻辑**：
- 首次打开 Settings → 查询 `SELECT DISTINCT agentic_tool` 取第一个 source → 再取第一个 provider → 再取第一个 model。
- 如果全表为空（没有任何 usage），Overview Section 直接显示空状态提示，不渲染 picker。

### 3.5 刷新频率

- 用户切换 filter → 立即刷新。
- 后台有新 usage 导入 → 通过 `appState.refreshOverview()` 增量刷新（轻量：只重新查询聚合）。

---

## 4. AppState 改动

在 `AppState` 中新增：

```swift
// MARK: - Overview (chart)
@Published public var overviewBuckets: [MinuteAggregation] = []
@Published public var overviewSource: String = ""           // 选中值；空字符串 = 尚未初始化
@Published public var overviewProvider: String = ""
@Published public var overviewModel: String = ""
@Published public var overviewAvailableSources: [String] = []
@Published public var overviewAvailableProviders: [String] = []
@Published public var overviewAvailableModels: [String] = []
@Published public var overviewYAxis: String = "tokens"      // "tokens" or "cost"

private static let overviewMaximumRange: TimeInterval = 24 * 60 * 60
private static let overviewMaximumBuckets = 24 * 60

public func refreshOverview() { ... }                         // 聚合 + 可选列表全量刷新
public func selectOverviewSource(_ source: String) { ... }    // 联动重置 provider/model
public func selectOverviewProvider(_ provider: String) { ... } // 联动重置 model
public func selectOverviewModel(_ model: String) { ... }      // 仅刷新图表
```

`refresh()` 中调用 `refreshOverview()` 联动刷新。

初始化时 `refreshOverview()` 的行为：
1. 查询 `SELECT DISTINCT agentic_tool` → 填充 `overviewAvailableSources`。
2. 如果为空 → 三个 selected 保持空字符串，UI 展示空状态。
3. 如果非空且 selected 为空 → 选中第一个 source → 联动选中第一个 provider → 联动选中第一个 model。
4. 计算 `overviewStartDate = max(timeRange.startDate, Date() - 24h)`；如果 Aggregation Range 为 `All`，则使用 `Date() - 24h`。
5. 最后根据选中的组合执行聚合查询填充 `overviewBuckets`，并将 `maxBuckets` 设为 1440。

---

## 5. 文件变更清单

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `Models/OverviewModels.swift` | **新增** | `MinuteAggregation` 模型 |
| `Database/TokenUsagesRepository.swift` | **修改** | 新增 `fetchMinuteAggregated`, `fetchDistinctProviders`, `fetchDistinctModels` |
| `Components/OverviewChartView.swift` | **新增** | 柱状图 SwiftUI 视图（含 Charts），使用原生横向滚动并保留左侧 Y 轴 |
| `Settings/SettingsTab.swift` | **修改** | 在 Form 顶部插入 Overview Section，新增 filter pickers + chart，并固定 legend 预留高度 |
| `App/AppState.swift` | **修改** | 新增 overview 状态属性与刷新方法，overview 时间窗口限制为 Aggregation Range 与最近 24 小时的交集 |

---

## 6. 数据流

```
source 变更
  ↓
selectOverviewSource("codex")
  ↓ 1. 查 providers = fetchDistinctProviders(for: "codex", since: overviewStartDate)
  ↓ 2. 取第一个 provider → 查 models = fetchDistinctModels(for: "codex", provider: first, since: overviewStartDate)
  ↓ 3. 取第一个 model → 聚合查询 fetchMinuteAggregated(source, provider, model, since: ...)
  ↓ 4. 更新 @Published → UI 重绘
```

后台新 usage 导入时：
```
LocalSourcesBackgroundService.onLiveTokensImported
  ↓
appState.refreshOverview()  // 额外调用，轻量 re-query
```

---

## 7. 实现顺序

1. **Step 1** — `OverviewModels.swift`：定义 `MinuteAggregation` 模型。
2. **Step 2** — `TokenUsagesRepository`：新增三个查询方法。
3. **Step 3** — `AppState`：新增 overview 状态 + filter/refresh 方法。
4. **Step 4** — `OverviewChartView.swift`：实现 Charts 柱状图组件。
5. **Step 5** — `SettingsTab.swift`：插入 Overview Section + filter bar + 集成。
6. **Step 6** — 测试：`swift build` + 手动验证。

---

## 8. 注意事项

- Swift Charts 需 `import Charts` 且在 macOS 13+ 可用（本项目 macOS 14+，满足）。
- GRDB `strftime` 基于 UTC；`created_at` 已是 ISO 8601 UTC 格式，无需转换。
- 聚合查询的 `LIMIT` 确保不会返回过多 bucket；Overview 默认上限为 1440，对应最近 24 小时的分钟桶上限。
- Filter picker 无 "All" 选项，始终需选中一个具体值。
- 空 table → Overview Section 直接显示 "No token usage recorded yet."，不渲染 picker 和 chart。
- 某个 source 下只有一个 provider/model 时，picker 无可选项但也正常展示，用户无需切换。
- 继承现有 `timeRange` 过滤。Overview 跟随 Settings 的 Aggregation Range，但最长只展示最近 24 小时。当 timeRange 变更时 `refreshOverview()` 会重新查询 picker 选项和 chart 数据。
