## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Time Range Selection

用户必须能选择不同的时间范围来查看菜单栏、Dashboard 汇总和 usage 列表统计；Dashboard overview 图表 MUST 保持当前本地日历日的 hourly breakdown。

#### Scenario: Time range changed
- **WHEN** 用户在菜单栏或 Dashboard/Settings 中切换时间范围（如今天/本周/本月）
- **THEN** 菜单栏、Dashboard 汇总和 usage 列表中的用量数据相应更新
- **AND** Dashboard overview 图表 MUST 继续展示当前本地日历日的 hourly buckets
