## Why

The current menu sends users to a Settings window that stacks overview, recent usage, local source status, and monitoring controls into one long form. The primary destination is really a usage dashboard, so the entry point and first screen should reflect that while still keeping detailed settings areas easy to reach.

## What Changes

- Rename the menu list entry from Settings to Dashboard while preserving the existing keyboard shortcut and window-opening behavior.
- Open the window to a Dashboard page/tab by default.
- Let the Dashboard window's tabs provide entry points to other task-oriented pages such as Usage, Sources, and Settings.
- Merge the existing Overview section into Dashboard: show dashboard summary content first, followed by the existing overview chart and its filters.
- Merge monitoring/display controls into a Settings page instead of keeping a standalone Monitoring page.
- Keep Local Sources as a Sources page because source health, errors, and manual rescan form a distinct operational workflow.
- Treat Recent Usage as a Usage page/detail area rather than exposing it as a literal section page.
- Avoid creating one page per old section; group content by user intent and keep the same shared `AppState` data flow.

## Capabilities

### New Capabilities

### Modified Capabilities
- `menu-bar-ui`: Menu bar menu must label the primary window entry as Dashboard, and the Dashboard window must open to a Dashboard tab with other task-oriented tabs available.

## Impact

- Affected UI code: `Sources/TokenLensApp/MenuBar/MenuBarView.swift`, `Sources/TokenLensApp/App/TokenLensApp.swift`, `Sources/TokenLensApp/Settings/SettingsView.swift`, and `Sources/TokenLensApp/Settings/SettingsTab.swift`.
- Possible supporting UI changes: extracted SwiftUI views for Dashboard, Usage, Sources, and Settings pages plus navigation selection state.
- App state and database schemas are not expected to change.
- Existing tests should continue to pass; implementation may add focused tests only if navigation or state behavior moves into testable logic.
