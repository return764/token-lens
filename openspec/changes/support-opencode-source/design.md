## Context

TokenLens currently treats local sources as JSONL producers in a few orchestration spots. `LocalUsageScanner`, `LocalSourcesBackgroundService`, and `LocalSourceImportQueue` discover session record files through `LocalUsageAdapter`, but they still perform JSONL-specific incremental reads before calling `parseLines`.

OpenCode's current local state is stored in SQLite at `~/.local/share/opencode/opencode.db`. The `session` table contains aggregate token and cost fields:

- `id`
- `directory`
- `model`
- `cost`
- `tokens_input`
- `tokens_output`
- `tokens_reasoning`
- `tokens_cache_read`
- `tokens_cache_write`
- `time_created`
- `time_updated`

Because those fields are cumulative per session, importing a whole session row repeatedly would double-count. OpenCode support must fit the same source/session-monitoring interface as Codex, Claude Code, and pi: detect changed session storage, read only usage-bearing session changes, emit `LocalUsageEvent` values, and let the existing repository handle import, cost, status, and dedup.

## Goals / Non-Goals

**Goals:**

- Add OpenCode as a built-in local source with id `opencode`.
- Import OpenCode session token and cost deltas from `~/.local/share/opencode/opencode.db`.
- Use one shared adapter/session-monitoring interface for both existing JSONL-backed sources and OpenCode's SQLite-backed source.
- Reuse existing `token_usages`, `local_usage_imports`, `local_scan_sources`, and `local_scan_files` tables.
- Preserve existing JSONL source behavior.
- Avoid storing prompts, responses, message bodies, tool outputs, auth data, or API keys.
- Support startup catch-up, background file changes, and periodic reconcile for OpenCode.

**Non-Goals:**

- Adding user-configurable source roots.
- Reading OpenCode prompts, messages, parts, events, todos, accounts, tool outputs, auth files, or share data.
- Migrating existing TokenLens tables.
- Estimating tokens for OpenCode rows that do not report token totals.
- Supporting legacy OpenCode storage formats beyond the current SQLite session aggregate schema.

## Decisions

1. **Generalize source reading at the adapter boundary.**

   Add a small adapter-level session read result API so scanners and queues ask each adapter to read usage events from a changed session record URL. This is the single compatibility interface for all built-in sources. The default implementation will keep the current JSONL behavior by using `LocalJSONLIncrementalReader`, `bootstrapContext`, and `parseLines`. `OpenCodeLocalUsageAdapter` will implement the same interface by querying SQLite session rows.

   Alternative considered: add a separate SQLite scanner path beside the JSONL scanner. That would duplicate source status, checkpoint, import queue, and watcher semantics even though both formats represent changing local sessions. Another alternative was to make OpenCode emit synthetic JSONL lines and feed them into `parseLines`; that would hide the cumulative-session problem and force SQLite checkpoint data into a JSONL-shaped interface.

2. **Represent the OpenCode database as one discovered local file.**

   `OpenCodeLocalUsageAdapter.defaultRoot` will be `~/.local/share/opencode`, and `discoverFiles()` will return `opencode.db` when present. Source status remains directory-based, while file checkpoint status tracks the database file path.

   Alternative considered: set `defaultRoot` directly to `opencode.db`. Existing watcher startup expects a directory, so this would require more service branching.

3. **Import cumulative session changes as deltas.**

   The adapter will store a compact per-session aggregate watermark in `parse_context_json`, keyed by OpenCode session id. For each session row, it will compute positive deltas between current aggregate values and the last imported aggregate:

   - input tokens
   - output tokens
   - reasoning tokens
   - cache read tokens
   - cache write tokens
   - cost

   Rows with no positive token or cost delta will not emit usage events. If a session's aggregate decreases, the adapter will treat it as a reset/fork and use the current positive aggregate as a new importable event while replacing that session's watermark.

   Alternative considered: use `session.id` as a native dedup key and import the full row once. That would miss later usage added to an ongoing session. Importing full rows on every update would double-count.

4. **Use stable delta event keys.**

   OpenCode delta events will use native ids derived from session id plus the row's update timestamp and aggregate fingerprint, for example `session:<id>:updated:<time_updated>:<fingerprint>`. This keeps repeated scans idempotent while allowing later positive deltas to import.

5. **Map OpenCode fields conservatively.**

   The adapter will map:

   - `sourceTool`: `opencode`
   - `sourceFile`: database path
   - `sourceSessionId`: `session.id`
   - `sourceCwd`: `session.directory`
   - `timestamp`: `time_updated`, falling back to `time_created`
   - `providerId` and `model`: parsed from `session.model` when it is valid JSON with provider/model fields; otherwise leave unavailable
   - token fields: matching `tokens_*` columns
   - `costUsd`: source-provided OpenCode delta cost when positive

   When model metadata is unavailable, the existing repository fallback provider behavior can still import usage with provider `opencode`; source-provided cost prevents a missing model price from zeroing cost.

6. **Make watcher candidate discovery adapter-aware.**

   The current `FileSystemEventWatcher` only returns `.jsonl` files. OpenCode writes through SQLite sidecar files such as `opencode.db-wal`, so the watcher path filtering must become source-aware. A simple approach is to let each adapter normalize raw changed paths into import candidates. JSONL adapters keep the current JSONL expansion; OpenCode maps `opencode.db`, `opencode.db-wal`, `opencode.db-shm`, or the root directory to the single `opencode.db` candidate.

7. **Keep old implementations as first-class compatibility paths.**

   Codex, Claude Code, and pi must continue to implement the same adapter interface and retain their existing parsing semantics. The unified interface should add default methods or lightweight wrapper types rather than requiring large rewrites of the three current adapters.

## Risks / Trade-offs

- [Risk] OpenCode changes its SQLite schema. → Mitigation: validate required columns before reading, mark the source or file as `parse_error` with sanitized error text, and cover missing-column behavior in tests.
- [Risk] `parse_context_json` grows with many OpenCode sessions. → Mitigation: store only session id and numeric aggregate watermarks, prune archived/unchanged entries opportunistically after each scan if needed.
- [Risk] OpenCode has uncheckpointed WAL data during read. → Mitigation: open the database read-only through SQLite/GRDB and rely on SQLite's normal snapshot behavior rather than reading raw files.
- [Risk] Aggregate reset/fork behavior could create an extra event. → Mitigation: only emit when current aggregate has positive values, generate a new fingerprinted native id, and update the watermark atomically with import.
- [Risk] Existing JSONL sources regress during scanner abstraction. → Mitigation: keep the default adapter/session read implementation semantically identical, make JSONL compatibility explicit in tests, and run existing Codex, Claude Code, pi, incremental reader, watcher, and scanner tests.
