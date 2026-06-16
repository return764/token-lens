## Context

`SettingsView` currently wraps `SettingsTab` in a vertical `ScrollView`. `SettingsTab` renders one grouped `Form` containing Overview, Recent Usage, Local Sources, and Monitoring sections. `MenuBarView` labels the primary window action as "Settings", and `AppDelegate` opens a window titled "TokenLens Settings". That works for the MVP, but the primary user-facing destination is a usage dashboard, while configuration belongs in secondary pages.

The change is UI-scoped. Existing data comes from `AppState`, repositories, and local scanning services; those contracts should remain unchanged.

## Goals / Non-Goals

**Goals:**
- Rename the menu-list action from Settings to Dashboard while keeping the same shortcut and window-opening flow.
- Present Dashboard as the default first page/tab inside the existing window.
- Put dashboard summary content above the existing overview chart and filters.
- Provide tab navigation in the Dashboard window for task-oriented pages, including Usage, Sources, and Settings.
- Combine related content instead of mapping every old form section to a page.
- Preserve shared `AppState` refresh behavior.
- Keep Usage, Sources, Settings controls, and Overview chart behavior equivalent to the current sections.
- Make future settings pages straightforward to add without growing one combined form.

**Non-Goals:**
- No database schema changes.
- No changes to local scanning, pricing sync, token aggregation, or privacy behavior.
- No new windows per section.
- No new app-wide routing framework.
- No renaming of repository/database `settings` concepts; this is a user-facing UI label change.

## Decisions

1. Use a SwiftUI navigation container with a stable page enum whose default value is Dashboard.
   - Rationale: a small enum such as `DashboardPage` or `SettingsPage` gives each page a stable identity, title, and icon/label while keeping navigation local to this window. Making Dashboard the first/default case aligns the menu entry with what users see after opening the window.
   - Alternative considered: keep a single `Form` with disclosure groups. That reduces scrolling only slightly and does not create distinct pages.

2. Fold the existing Overview section into Dashboard instead of keeping it as a separate "Overview" destination.
   - Rationale: the overview chart is the core dashboard content, but the user should first see high-level dashboard information before the chart.
   - Alternative considered: keep a standalone Overview page and add a separate Dashboard page. That would create two highly overlapping destinations.

3. Group old sections by user intent rather than by their current code boundaries.
   - Dashboard: summary metrics first, then the overview chart and filters, without an extra Pages section.
   - Usage: recent usage/details, because this is about inspecting recorded usage events.
   - Sources: local source health and `Rescan Now`, because this is an operational/status workflow.
   - Settings: menu bar display, live usage mode, aggregation range, and future preferences, because these are configuration controls.
   - Rationale: this keeps pages meaningful and prevents a thin one-page-per-section structure.
   - Alternative considered: create pages for Overview, Recent Usage, Local Sources, and Monitoring. That mirrors the old implementation too closely and makes Monitoring feel like a page when it is really settings content.

4. Keep `AppState` as the single source of truth.
   - Rationale: filters, chart data, recent usage, local sources, and monitoring settings already live in `AppState`; navigation should not duplicate or cache this state.
   - Alternative considered: introduce per-page view models. That adds indirection without a current need because no new business logic is being introduced.

5. Refresh when the Dashboard/Settings container appears, not independently for every page.
   - Rationale: the current `onAppear { appState.refresh() }` behavior should remain predictable and avoid redundant refreshes when users switch pages.
   - Alternative considered: refresh each page on appearance. That could create unnecessary database reads while navigating.

6. Keep implementation symbols conservative even if labels change.
   - Rationale: methods such as `openSettings()` and database settings remain accurate internal concepts. User-facing text can become Dashboard without forcing broad renames.
   - Alternative considered: rename all internal Settings symbols to Dashboard. That increases churn and touches unrelated app lifecycle code.

## Risks / Trade-offs

- [Risk] Dashboard label may conflict with internal Settings naming. -> Mitigation: keep internal names stable where useful and update only user-facing menu/window/page labels.
- [Risk] Dashboard could become crowded if it contains both summaries, chart, and all detail content. -> Mitigation: keep Dashboard to summary and overview chart; use window-level tabs for Usage, Sources, and Settings.
- [Risk] macOS navigation styling could make the Dashboard window feel too sparse if pages are narrow. -> Mitigation: set sensible minimum window dimensions and let content use the available detail pane width.
- [Risk] Extracting sections may accidentally change bindings or refresh behavior. -> Mitigation: move existing code with minimal behavioral edits and verify `swift build` plus `swift test`.
- [Risk] UI-only behavior is hard to cover with existing unit tests. -> Mitigation: keep logic in `AppState`, limit page code to bindings/rendering, and rely on build/tests plus manual UI smoke testing when implementing.
