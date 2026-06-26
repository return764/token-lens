## 1. Unified Session Source Interface

- [x] 1.1 Add an adapter-level session read result type in `Sources/TokenLensApp/Core/LocalRecords/LocalUsageModels.swift` that contains events plus checkpoint metadata.
- [x] 1.2 Add a default session read method that preserves the current JSONL flow using `LocalJSONLIncrementalReader`, `bootstrapContext`, and `parseLines`.
- [x] 1.3 Update `LocalUsageScanner` to call the unified adapter session read method instead of directly reading JSONL lines.
- [x] 1.4 Update `LocalSourceImportQueue` to call the same unified adapter session read method for background imports.
- [x] 1.5 Keep Codex, Claude Code, and pi on the same interface through defaults or minimal wrappers, without changing their parser behavior.

## 2. Watcher Candidate Routing

- [x] 2.1 Add adapter-aware candidate normalization for raw FSEvent paths, keeping existing JSONL directory expansion for current sources.
- [x] 2.2 Update `LocalSourcesBackgroundService` watcher callbacks to use adapter candidate normalization.
- [x] 2.3 Add tests that existing JSONL paths still expand and dedupe correctly through the same source interface.

## 3. OpenCode Source Implementation

- [x] 3.1 Create `Sources/TokenLensApp/Core/LocalRecords/OpenCodeLocalUsageAdapter.swift` with id `opencode`, display name `OpenCode`, root `~/.local/share/opencode`, and discovery of `opencode.db`.
- [x] 3.2 Implement read-only SQLite session querying for required OpenCode fields and sanitized errors for unsupported schema.
- [x] 3.3 Implement compact parse context watermarks for per-session aggregate token and cost totals.
- [x] 3.4 Emit only positive OpenCode usage deltas as `LocalUsageEvent` values with stable native keys.
- [x] 3.5 Map OpenCode source metadata to session id, cwd, timestamp, provider/model when available, token dimensions, total tokens, and source-provided cost.
- [x] 3.6 Normalize OpenCode FSEvent paths from `opencode.db`, `opencode.db-wal`, `opencode.db-shm`, and the data directory to the `opencode.db` candidate.

## 4. Registration and Documentation

- [x] 4.1 Register `OpenCodeLocalUsageAdapter()` in `LocalUsageScanner.defaultAdapters()`.
- [x] 4.2 Update local source documentation and project source lists to include OpenCode and its SQLite path.
- [x] 4.3 Confirm Settings/Local Sources display uses the OpenCode adapter display name without additional UI changes.

## 5. Tests and Verification

- [x] 5.1 Add `OpenCodeLocalUsageAdapterTests` covering initial import, unchanged aggregate no-op, positive delta import, aggregate reset, unsupported schema, and privacy-safe table access.
- [x] 5.2 Update `LocalUsageScannerTests` default adapter expectations to include `opencode`.
- [x] 5.3 Add scanner/import queue compatibility tests proving JSONL sources and OpenCode use the same adapter session read path.
- [x] 5.4 Add watcher/service tests for OpenCode sidecar file normalization and existing JSONL regression coverage.
- [x] 5.5 Run `swift test` and fix regressions.
