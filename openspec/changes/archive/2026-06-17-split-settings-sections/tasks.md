## 1. Dashboard Entry Point

- [x] 1.1 Change the menu popover action label from `Settings` to `Dashboard` in `Sources/TokenLensApp/MenuBar/MenuBarView.swift` while preserving the `⌘,` shortcut and existing open action.
- [x] 1.2 Change the macOS app menu item and user-facing window title from Settings wording to Dashboard wording in `Sources/TokenLensApp/App/TokenLensApp.swift`.
- [x] 1.3 Keep internal settings persistence and app state naming unchanged unless a narrow rename is needed for clarity.

## 2. Dashboard Navigation Structure

- [x] 2.1 Add a local page model/enum for Dashboard, Usage, Sources, and Settings in `Sources/TokenLensApp/Settings/SettingsTab.swift` or a focused companion file.
- [x] 2.2 Replace the single long Settings form with a SwiftUI tab navigation structure that defaults to the Dashboard tab and exposes detail tabs in `Sources/TokenLensApp/Settings/SettingsTab.swift`.
- [x] 2.3 Keep `SettingsView` responsible for the window wrapper and ensure the new navigation layout has suitable minimum dimensions in `Sources/TokenLensApp/Settings/SettingsView.swift`.
- [x] 2.4 Keep one window-level refresh on appearance so page switching does not trigger redundant refresh work.

## 3. Page Extraction

- [x] 3.1 Build the Dashboard page with summary content first, then the existing overview chart and filters, without changing its `AppState` bindings or chart behavior.
- [x] 3.2 Use window-level tabs as entry controls for Usage, Sources, and Settings pages without adding a Pages section to Dashboard.
- [x] 3.3 Move the current Recent Usage section UI into a Usage page without changing list formatting or empty-state behavior.
- [x] 3.4 Move the current Local Sources section UI into a Sources page and preserve source status display plus the `Rescan Now` action.
- [x] 3.5 Move the current Monitoring section UI into a Settings page and preserve menu bar display, live usage mode, and aggregation range persistence behavior.
- [x] 3.6 Avoid creating standalone pages for Overview or Monitoring; keep those concerns merged into Dashboard and Settings respectively.

## 4. Verification

- [x] 4.1 Add focused tests for any new testable navigation/page-selection logic, or document why the change remains presentation-only with existing `AppState` unit coverage.
- [x] 4.2 Run `swift build` to verify the SwiftUI extraction compiles.
- [x] 4.3 Run `swift test` to verify existing app state, repository, and local scanning behavior remains unchanged.
- [x] 4.4 Manually smoke test the menu and window to confirm the menu says Dashboard, Dashboard opens first, summary content appears above the overview chart, no Pages section appears, and Usage/Sources/Settings are reachable from tabs.
