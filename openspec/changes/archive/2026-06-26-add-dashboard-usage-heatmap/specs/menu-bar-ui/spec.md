## ADDED Requirements

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
