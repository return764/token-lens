## 1. Core Models and Protocol

- [x] 1.1 Add `LocalUsageRecord` and `LocalUsageRecordKind` in `Sources/TokenLensApp/Core/LocalRecords/LocalUsageModels.swift`
- [x] 1.2 Replace `LocalUsageAdapter` with the final record-oriented protocol in `LocalUsageModels.swift`
- [x] 1.3 Remove old adapter protocol methods and default implementations from `LocalUsageModels.swift`
- [x] 1.4 Update or remove test stubs that still implement `discoverFiles`, `checkpointURL`, `readSessionChanges`, `parseFile`, `bootstrapContext`, or `parseLines`

## 2. JSONL Reader Extraction

- [x] 2.1 Add `AppendOnlyJSONLUsageReader` under `Sources/TokenLensApp/Core/LocalRecords/`
- [x] 2.2 Move JSONL read/checkpoint construction logic from the old adapter extension into `AppendOnlyJSONLUsageReader`
- [x] 2.3 Add source-specific JSONL decoder support for initial parse context and line parsing
- [x] 2.4 Keep `LocalJSONLIncrementalReader` behavior unchanged and verify existing incremental reader tests still pass

## 3. Scanner, Queue, and Watcher Flow

- [x] 3.1 Update `LocalUsageScanner` to call `discoverRecords()` and `readUsageChanges(record:checkpoint:)`
- [x] 3.2 Update scanner checkpoint and file status lookup to use `record.checkpointURL.path`
- [x] 3.3 Update `LocalSourceImportQueue` to enqueue `LocalUsageRecord` values and deduplicate by source id plus checkpoint path
- [x] 3.4 Remove URL-based import queue entry points from `LocalSourceImportQueue`
- [x] 3.5 Update `LocalSourcesBackgroundService` watcher callbacks to enqueue adapter-normalized records
- [x] 3.6 Update periodic reconcile to discover records and compare checkpoint status using `record.checkpointURL`

## 4. Built-in Adapter Conversion

- [x] 4.1 Convert `PiLocalUsageAdapter` to discover append-only JSONL records and read through `AppendOnlyJSONLUsageReader`
- [x] 4.2 Convert `ClaudeCodeLocalUsageAdapter` to discover append-only JSONL records and read through `AppendOnlyJSONLUsageReader`
- [x] 4.3 Convert `CodexLocalUsageAdapter` to discover append-only JSONL records and preserve bootstrap context rebuild through the new JSONL helper
- [x] 4.4 Convert `OpenCodeLocalUsageAdapter` to discover only the main `opencode.db` logical record
- [x] 4.5 Update OpenCode candidate normalization so `opencode.db`, `opencode.db-wal`, `opencode.db-shm`, and root changes map to the main database record
- [x] 4.6 Delete OpenCode's empty JSONL parser methods

## 5. Tests

- [x] 5.1 Update `PiLocalUsageAdapterTests`, `ClaudeCodeLocalUsageAdapterTests`, and `CodexLocalUsageAdapterTests` for record-based reads
- [x] 5.2 Update `OpenCodeLocalUsageAdapterTests` to assert `discoverRecords()` returns only `opencode.db`
- [x] 5.3 Add OpenCode WAL/SHM candidate tests asserting sidecar changes map to the main database checkpoint record
- [x] 5.4 Update `LocalUsageScannerTests` to assert scanner uses `readUsageChanges(record:checkpoint:)`
- [x] 5.5 Update import queue tests to assert DB and WAL events deduplicate by checkpoint path
- [x] 5.6 Update `FileSystemEventWatcherTests` and privacy tests for record candidate behavior
- [x] 5.7 Run `swift test` and fix regressions

## 6. Documentation and Validation

- [x] 6.1 Update `PROJECT_SPEC.md` to describe record-oriented local adapters
- [x] 6.2 Update `docs/adding-new-local-source.md` to document JSONL and SQLite adapter patterns
- [x] 6.3 Update `docs/plans/current/local-usage-adapter-redesign-plan.md` if implementation decisions differ from the plan
- [x] 6.4 Run OpenSpec validation/status for `redesign-local-usage-adapter`
