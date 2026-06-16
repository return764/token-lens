## MODIFIED Requirements

### Requirement: Settings Window

系统必须提供独立的 Dashboard 窗口，默认展示 Dashboard tab，并通过窗口 tab 进入按任务分组的详细页面。

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

### Requirement: Menu Bar Menu

菜单栏的下拉菜单必须提供快速访问功能，并将主窗口入口标记为 Dashboard。

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
