## Purpose

通过 macOS MenuBarExtra 和独立 Settings 窗口展示 token 用量数据，支持时间范围筛选和实时新用量提示。

## Requirements

### Requirement: Menu Bar Cost Display

菜单栏必须显示选定时间范围内的累计 cost 或 token 用量。

#### Scenario: Default display
- **WHEN** 应用正常运行且用户未交互
- **THEN** 菜单栏显示选定时间范围内的总 cost（如 "$0.42"）或总 tokens

#### Scenario: No usage data
- **WHEN** 选定时间范围内无任何 usage 记录
- **THEN** 菜单栏显示 "$0.00" 或 "0 tokens"

### Requirement: Live Token Display on New Import

当有新的 usage 事件被导入时，菜单栏必须短暂显示这次使用的 input/output tokens。

#### Scenario: New usage imported
- **WHEN** 系统导入一个新的 usage 事件
- **THEN** 菜单栏临时切换显示新导入的 input/output tokens（如 "↑1,200 ↓800"）
- **AND** 短暂显示后恢复到正常的累计 cost/tokens 显示

### Requirement: Settings Window

系统必须提供独立的 Settings 窗口，展示用量详情和 source 状态。

#### Scenario: Settings window opened
- **WHEN** 用户通过菜单栏菜单打开 Settings
- **THEN** 显示一个独立的 SwiftUI Settings 窗口

#### Scenario: Recent usage display
- **WHEN** Settings 窗口打开
- **THEN** 显示最近的 token 用量列表

#### Scenario: Local Sources status display
- **WHEN** Settings 窗口打开
- **THEN** 显示每个 Local Source（Codex、Claude Code、pi）的状态信息：
  - 状态（ready/scanning/unavailable）
  - 最后扫描时间
  - 已导入事件数
  - 错误数（如有）

#### Scenario: Monitoring display settings
- **WHEN** Settings 窗口打开
- **THEN** 提供监控显示相关设置选项

### Requirement: Time Range Selection

用户必须能选择不同的时间范围来查看用量统计。

#### Scenario: Time range changed
- **WHEN** 用户在菜单栏或 Settings 中切换时间范围（如今天/本周/本月）
- **THEN** 菜单栏和 Settings 中的用量数据相应更新

### Requirement: Menu Bar Menu

菜单栏的下拉菜单必须提供快速访问功能。

#### Scenario: Menu opened
- **WHEN** 用户点击菜单栏图标
- **THEN** 菜单包含：
  - 当前用量概览
  - 打开 Settings 选项
  - 退出应用选项
