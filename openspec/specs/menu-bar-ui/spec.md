## Purpose

通过 macOS MenuBarExtra 和独立 Dashboard 窗口展示 token 用量数据，支持时间范围筛选和实时新用量提示。
## Requirements
### Requirement: Menu Bar Cost Display

菜单栏 MUST 显示选定时间范围内的累计 cost 或 token 用量。

#### Scenario: Default display
- **WHEN** 应用正常运行且用户未交互
- **THEN** 菜单栏显示选定时间范围内的总 cost（如 "$0.42"）或总 tokens

#### Scenario: No usage data
- **WHEN** 选定时间范围内无任何 usage 记录
- **THEN** 菜单栏显示 "$0.00" 或 "0 tokens"

### Requirement: Live Token Display on New Import

当有新的 usage 事件被导入时，菜单栏 MUST 短暂显示这次使用的 input/output tokens。

#### Scenario: New usage imported
- **WHEN** 系统导入一个新的 usage 事件
- **THEN** 菜单栏临时切换显示新导入的 input/output tokens（如 "↑1,200 ↓800"）
- **AND** 短暂显示后恢复到正常的累计 cost/tokens 显示

### Requirement: Settings Window

系统 MUST 提供独立的 Dashboard 窗口，默认展示 Dashboard tab，并通过窗口 tab 进入按任务分组的详细页面。

#### Scenario: Settings window opened
- **WHEN** 用户通过菜单栏菜单打开 Dashboard
- **THEN** 显示一个独立的 SwiftUI Dashboard 窗口
- **AND** 窗口默认选中 Dashboard 页面/tab
- **AND** 窗口提供 Usage、Sources、Settings 等详细 tab 入口

#### Scenario: Dashboard page navigation
- **WHEN** Dashboard 窗口打开
- **AND** 用户选择某个详细 tab 入口
- **THEN** 窗口主内容区域显示所选页面
- **AND** 用户能通过 Dashboard tab 返回 Dashboard 页面
- **AND** 页面不是按照旧 Settings section 一节一页机械拆分

#### Scenario: Dashboard page display
- **WHEN** 用户打开 Dashboard 页面
- **THEN** 页面顶部显示 dashboard 汇总内容
- **AND** 汇总内容下方显示现有 overview 图表与 source/provider/model/y-axis 过滤控件
- **AND** 页面不显示额外的 Pages 区块

#### Scenario: Usage page display
- **WHEN** 用户打开 Usage tab
- **THEN** 显示最近的 token 用量列表

#### Scenario: Sources page display
- **WHEN** 用户打开 Sources tab
- **THEN** 显示每个 Local Source（Codex、Claude Code、pi）的状态信息：
  - 状态（ready/scanning/unavailable）
  - 最后扫描时间
  - 已导入事件数
  - 错误数（如有）
- **AND** 提供手动重新扫描入口

#### Scenario: Settings page display
- **WHEN** 用户打开 Settings tab
- **THEN** 提供监控显示相关设置选项
- **AND** 显示设置合并在 Settings 页面内，而不是作为独立 Monitoring 页面

### Requirement: Dashboard Overview Hourly Buckets

Dashboard overview 图表 MUST 按当前本地日历日的每小时 bucket 展示用量分布。

#### Scenario: Dashboard overview uses today's hourly buckets
- **WHEN** 用户打开 Dashboard 页面
- **THEN** overview 图表查询范围 MUST 从当前本地日期的 00:00:00 开始
- **AND** 查询范围 MUST 在下一本地日期的 00:00:00 之前结束
- **AND** 图表 MUST 将同一小时内的 usage 聚合到同一个 hourly bucket
- **AND** 图表 x 轴 MUST 覆盖当天 00:00 到 23:00 的每一个小时，即使某些小时没有 usage

#### Scenario: Hourly bucket totals preserve token and cost dimensions
- **WHEN** 同一个 source/provider/model 在同一小时内有多条 usage 记录
- **THEN** overview hourly bucket MUST 汇总 input、output、cached input、cache write、reasoning、total tokens、cost 和 request count

#### Scenario: Overview filters still apply
- **WHEN** 用户切换 overview 的 source、provider、model 或 y-axis 过滤控件
- **THEN** overview 图表 MUST 继续使用当天 hourly buckets
- **AND** 图表 MUST 只展示符合所选 source/provider/model 的 usage

#### Scenario: Usage outside today is excluded
- **WHEN** 数据库中存在早于今天 00:00:00 或晚于等于明天 00:00:00 的 usage
- **THEN** 这些 usage MUST NOT 出现在 Dashboard overview hourly buckets 中

### Requirement: Time Range Selection

用户必须能选择不同的时间范围来查看菜单栏、Dashboard 汇总和 usage 列表统计；Dashboard overview 图表 MUST 保持当前本地日历日的 hourly breakdown。

#### Scenario: Time range changed
- **WHEN** 用户在菜单栏或 Dashboard/Settings 中切换时间范围（如今天/本周/本月）
- **THEN** 菜单栏、Dashboard 汇总和 usage 列表中的用量数据相应更新
- **AND** Dashboard overview 图表 MUST 继续展示当前本地日历日的 hourly buckets

### Requirement: Menu Bar Menu

菜单栏的下拉菜单 MUST 提供快速访问功能，并将主窗口入口标记为 Dashboard。

#### Scenario: Menu opened
- **WHEN** 用户点击菜单栏图标
- **THEN** 菜单包含：
  - 当前用量概览
  - 打开 Dashboard 选项
  - 退出应用选项

#### Scenario: Dashboard opened from menu
- **WHEN** 用户点击菜单中的 Dashboard 选项
- **THEN** 系统打开 Dashboard 窗口
- **AND** Dashboard 页面/tab 首先显示

### Requirement: Dashboard Daily Usage Heatmap

Dashboard 页面 MUST 展示一个日期热力图，以最近 53 周的本地日历日期为网格展示每日 token usage 强度。

#### Scenario: Dashboard heatmap displays recent daily activity
- **WHEN** 用户打开 Dashboard 页面
- **THEN** Dashboard MUST 在汇总内容附近展示日期热力图
- **AND** 热力图 MUST 覆盖包含今天在内的最近 53 周本地日历日期
- **AND** 热力图 MUST 按周为列、按星期为行排列日期单元格
- **AND** 热力图 MUST 显示月份标签和 weekday 参考标签

#### Scenario: Daily cells aggregate usage by local date
- **WHEN** 同一本地日期内存在多条 usage 记录
- **THEN** 对应该日期的 heatmap 单元格 MUST 汇总 input、output、cached input、cache write、reasoning、total tokens、cost 和 request count
- **AND** 同一天内来自不同 source、provider 或 model 的 usage MUST 汇总到同一个日期单元格

#### Scenario: Zero-usage dates remain visible
- **WHEN** 最近 53 周内某个本地日期没有 usage 记录
- **THEN** heatmap MUST 仍显示该日期单元格
- **AND** 该单元格 MUST 使用零用量视觉状态

#### Scenario: Heatmap cell intensity reflects daily consumption
- **WHEN** 日期单元格存在 usage
- **THEN** heatmap MUST 使用离散色阶表达该日期的相对消耗强度
- **AND** cost 大于 0 的数据集 MUST 以 daily cost 作为强度依据
- **AND** 当所有 daily cost 都为 0 但存在 tokens 时，heatmap MUST 以 daily total tokens 作为强度依据

#### Scenario: Hovering a day shows usage tooltip
- **WHEN** 用户将鼠标 hover 到某个日期单元格
- **THEN** Dashboard MUST 显示 tooltip
- **AND** tooltip MUST 包含本地日期、cost、total tokens、input tokens、output tokens 和 request count
- **AND** tooltip MUST NOT 显示 prompt、response、tool output、Authorization 或 API key

#### Scenario: New imports refresh heatmap
- **WHEN** 系统导入新的 usage 事件
- **THEN** Dashboard heatmap MUST 在下一次 Dashboard refresh 中反映新的 daily aggregate
- **AND** 不得要求用户重启应用才能看到新的日期强度或 tooltip 统计

