## Why

TokenLens currently tracks Codex, Claude Code, and pi usage, but OpenCode sessions are invisible even though OpenCode stores local token and cost totals. Supporting OpenCode closes a common local-agent gap while preserving TokenLens' local-first, no-content-storage model.

## What Changes

- Add OpenCode as a built-in local source with source id `opencode` and display name `OpenCode`.
- Discover OpenCode's default local database at `~/.local/share/opencode/opencode.db`.
- Use one source adapter/session-monitoring interface for both existing JSONL sources and OpenCode, because all built-in sources are fundamentally session records that change over time.
- Import usage-bearing OpenCode session records into `token_usages`, mapping session token deltas to input, output, cache read, cache write, reasoning, total tokens, and source-provided cost.
- Track OpenCode scan state through the existing local source status/checkpoint tables so startup catch-up, watcher/reconcile behavior, and duplicate prevention remain consistent with other sources.
- Preserve privacy guarantees by reading only OpenCode metadata and aggregate usage fields, never prompt, response, tool output, auth, or API-key data.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `local-scanning`: Built-in source discovery and scanning must include OpenCode's local SQLite database in addition to existing JSONL sources.
- `usage-tracking`: `token_usages.agentic_tool` must accept and report OpenCode usage under `opencode`.

## Impact

- Affected code:
  - `Sources/TokenLensApp/Core/LocalRecords/LocalUsageModels.swift`
  - `Sources/TokenLensApp/Core/LocalRecords/LocalUsageScanner.swift`
  - `Sources/TokenLensApp/Core/LocalRecords/LocalSourcesBackgroundService.swift`
  - `Sources/TokenLensApp/Core/LocalRecords/LocalSourceImportQueue.swift`
  - unified session-source adapter extensions and new OpenCode adapter/reader under `Sources/TokenLensApp/Core/LocalRecords/`
  - tests under `Tests/TokenLensTests/`
- Affected specs:
  - `openspec/specs/local-scanning/spec.md`
  - `openspec/specs/usage-tracking/spec.md`
- No database migration is expected for `token_usages`; the new source should reuse existing usage and import tables.
- No new external network dependency is introduced.
