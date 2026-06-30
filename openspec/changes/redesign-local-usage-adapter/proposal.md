## Why

`LocalUsageAdapter` is currently half unified and half JSONL-specific: scanners call a unified read method, but every adapter is still forced to expose JSONL parser methods. This makes SQLite-backed sources like OpenCode fit poorly and creates duplicate scan/checkpoint behavior around WAL sidecar files.

This change makes the adapter boundary describe local usage records rather than JSONL files, so JSONL and SQLite sources share one clean scanning/import path without compatibility shims.

## What Changes

- **BREAKING** Replace the `LocalUsageAdapter` protocol with a smaller record-oriented interface:
  - `discoverRecords()`
  - `candidates(fromChangedPaths:)`
  - `readUsageChanges(record:checkpoint:)`
- **BREAKING** Remove adapter-level compatibility methods:
  - `discoverFiles()`
  - `checkpointURL(for:)`
  - `readSessionChanges(file:checkpoint:)`
  - `parseFile(_:)`
  - `bootstrapContext(file:checkpoint:)`
  - `parseLines(_:file:context:)`
- Add `LocalUsageRecord` to represent the logical record being read, including:
  - `readURL`
  - `checkpointURL`
  - `displayPath`
  - record kind such as append-only JSONL or SQLite database
- Move append-only JSONL incremental reading into a shared helper used by Codex, Claude Code, and pi adapters.
- Keep JSONL parser semantics source-specific while removing JSONL parser requirements from the main adapter protocol.
- Make scanner, background service, import queue, and reconcile logic operate on `LocalUsageRecord`.
- Make OpenCode discover only the main database as a logical record while mapping `opencode.db-wal` and `opencode.db-shm` changes back to that main database record.
- Reuse existing local scan and usage tables; no database migration is expected.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `local-scanning`: Local scanning must operate on adapter-provided logical usage records instead of raw JSONL file URLs, and the built-in adapter interface must not retain JSONL-only compatibility methods.
- `usage-tracking`: Usage events must continue to preserve event-level deduplication and non-sensitive parse context when produced from either append-only JSONL records or SQLite database records.

## Impact

- Affected source files:
  - `Sources/TokenLensApp/Core/LocalRecords/LocalUsageModels.swift`
  - `Sources/TokenLensApp/Core/LocalRecords/LocalUsageScanner.swift`
  - `Sources/TokenLensApp/Core/LocalRecords/LocalSourcesBackgroundService.swift`
  - `Sources/TokenLensApp/Core/LocalRecords/LocalSourceImportQueue.swift`
  - `Sources/TokenLensApp/Core/LocalRecords/LocalJSONLIncrementalReader.swift`
  - built-in local adapters under `Sources/TokenLensApp/Core/LocalRecords/`
- Affected tests:
  - adapter tests for Codex, Claude Code, pi, and OpenCode
  - scanner/import queue tests
  - watcher candidate tests
  - privacy tests
- Affected docs:
  - `PROJECT_SPEC.md`
  - `docs/adding-new-local-source.md`
  - current plan in `docs/plans/current/`
- No new network dependency, CLI tool, cloud sync, prompt saving, Windows/Linux support, or network capture is introduced.
