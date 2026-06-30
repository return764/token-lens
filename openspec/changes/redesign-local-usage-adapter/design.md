## Context

TokenLens local source ingestion has grown from append-only JSONL files to SQLite-backed session records. The current `LocalUsageAdapter` protocol already has a unified read result, but still requires JSONL-only methods such as `parseFile`, `bootstrapContext`, and `parseLines`. That forces OpenCode to provide meaningless parser methods and leaves scanner/queue code passing raw `URL` values even when the logical checkpoint target differs from the changed file path.

The redesign makes the adapter boundary represent logical local usage records. A record may be an append-only JSONL session file or a SQLite database. Scanner, watcher, queue, and repository code will depend on record discovery and usage-change reads only; format-specific parsing remains inside adapters and helpers.

## Goals / Non-Goals

**Goals:**

- Replace raw file URLs at the adapter boundary with `LocalUsageRecord`.
- Remove all JSONL-only compatibility methods from `LocalUsageAdapter`.
- Keep one scanner/import path for Codex, Claude Code, pi, and OpenCode.
- Keep append-only JSONL incremental reading as a shared helper rather than protocol behavior.
- Ensure OpenCode WAL/SHM changes enqueue the main database checkpoint exactly once.
- Preserve existing storage tables and privacy boundaries.

**Non-Goals:**

- No database migration.
- No CLI tooling.
- No network capture, MITM, HTTPS decryption, or Network Extension.
- No prompt, response, tool output, auth, or API-key storage.
- No cloud sync.
- No Windows/Linux support.
- No new local source beyond the already planned built-in sources.

## Decisions

1. **Use `LocalUsageRecord` as the adapter boundary.**

   Each record carries `readURL`, `checkpointURL`, `displayPath`, and `kind`. JSONL records use the same URL for reading and checkpointing. OpenCode sidecar changes map back to a record whose `readURL` and `checkpointURL` both point to `opencode.db`.

   Alternative considered: keep raw URLs and `checkpointURL(for:)`. That keeps the old ambiguity: a watcher event path can be a WAL file while the logical checkpoint belongs to the main database.

2. **Make `LocalUsageAdapter` a final, minimal protocol.**

   The protocol will contain only source metadata, record discovery, candidate normalization, and `readUsageChanges(record:checkpoint:)`. The old `discoverFiles`, `checkpointURL`, `readSessionChanges`, `parseFile`, `bootstrapContext`, and `parseLines` methods are removed with no compatibility layer.

   Alternative considered: keep default bridges during migration. This was rejected because the goal is a clean interface and the project is small enough to update call sites and tests directly.

3. **Move JSONL behavior into an explicit helper.**

   `AppendOnlyJSONLUsageReader` will own offset reads via `LocalJSONLIncrementalReader`, complete-line handling, truncate/rotate behavior, checkpoint update construction, and parse-context persistence. JSONL adapters provide only source-specific line decoding and optional initial context rebuild.

   Alternative considered: make JSONL decoding another adapter protocol requirement. That would still leak JSONL concepts into the main adapter shape.

4. **Let SQLite adapters own their complete read path.**

   OpenCode will implement `readUsageChanges(record:checkpoint:)` directly by reading GRDB snapshots from the main database and comparing session aggregate values against parse-context watermarks. `readOffset` remains a file status field; SQLite's real import watermark stays in parse context.

   Alternative considered: synthesize JSONL-like lines from SQLite rows. That hides aggregate delta semantics and makes the checkpoint model harder to reason about.

5. **Deduplicate queue work by checkpoint path.**

   `LocalSourceImportQueue` will key pending/in-progress work by `(sourceTool, record.checkpointURL.path)`. Multiple sidecar events therefore converge on one import unit.

   Alternative considered: dedupe by changed path. That can import `opencode.db`, `opencode.db-wal`, and `opencode.db-shm` concurrently even though they represent one logical record.

## Risks / Trade-offs

- [Risk] Broad protocol breakage affects many tests. → Mitigation: update stubs to the final protocol and remove old parser stubs instead of maintaining two paths.
- [Risk] Record abstraction adds one new type to simple JSONL sources. → Mitigation: provide small construction helpers for append-only JSONL records while keeping the main protocol clearer.
- [Risk] SQLite `readOffset` is not a true usage watermark. → Mitigation: keep aggregate watermarks in parse context and treat file size as status/debug metadata only.
- [Risk] Existing JSONL behavior could regress during extraction. → Mitigation: keep `LocalJSONLIncrementalReader` unchanged and cover pi, Codex, Claude Code, scanner, and queue behavior with tests.
- [Risk] OpenCode WAL changes may be coalesced or missed by FSEvents. → Mitigation: periodic reconcile discovers the main database record and uses checkpoint context to catch up.

## Migration Plan

1. Add `LocalUsageRecord` and `LocalUsageRecordKind`.
2. Replace `LocalUsageAdapter` with the final record-oriented protocol.
3. Add `AppendOnlyJSONLUsageReader`.
4. Convert scanner, background service, import queue, and reconcile logic to `LocalUsageRecord`.
5. Convert Codex, Claude Code, and pi to JSONL record adapters.
6. Convert OpenCode to a SQLite record adapter that only discovers the main database.
7. Update tests and documentation.

Rollback is source-level only: revert the change if the new protocol cannot be completed in one implementation pass. No database migration means no persisted schema rollback is required.

## Open Questions

- Should `LocalUsageRecordKind` stay as a small enum, or should it be removed if it remains only diagnostic metadata?
- Should `displayPath` be persisted anywhere, or remain logging/UI-only in memory?
