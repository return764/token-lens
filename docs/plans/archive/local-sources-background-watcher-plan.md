# Local Sources 后台监听增量同步计划

> 状态：**Completed / Archived** — 2026-06-15  
> 最后更新：2026-06-15

## 1. 目标

将 Codex / Claude Code / pi 的本地 JSONL 扫描升级为 App 内后台服务：启动时补扫历史，运行时监听文件变化，只读取新增完整行，解析 usage 并写入 SQLite。

当前已实现。

## 2. 当前架构

```text
AppState
  ↓ start()
LocalSourcesBackgroundService
  ├─ LocalUsageScanner catch-up
  ├─ FileSystemEventWatcher（FSEvents）
  ├─ periodic reconcile
  └─ LocalSourceImportQueue
        ↓ debounce / serialize
LocalJSONLIncrementalReader
        ↓ complete lines only
LocalUsageAdapter.parseLines(..., context: &ctx)
        ↓
LocalScanRepository.importIncrementalUsageEvents
  ├─ INSERT local_usage_imports(key) for dedupe
  ├─ INSERT token_usages
  └─ UPSERT local_scan_files checkpoint in same transaction
```

## 3. 已实现行为

| 行为 | 状态 |
|---|---|
| 三个 source 始终启用 | ✅ |
| App 启动 catch-up scan | ✅ |
| FSEvents 监听 root 目录 | ✅ |
| root 不存在时定期重试 | ✅ |
| 周期 reconcile 兜底漏事件 | ✅ |
| 事件入队、防抖、串行导入 | ✅ |
| 只读取新增完整行 | ✅ |
| 文件尾半行不推进 offset | ✅ |
| 文件截断/轮转从 0 重读 | ✅ |
| 重复事件由 key 去重 | ✅ |
| checkpoint 与 usage 导入同事务 | ✅ |
| 导入后刷新 UI / live token display | ✅ |

## 4. 当前实现文件

| 文件 | 职责 |
|---|---|
| `Core/LocalRecords/LocalSourcesBackgroundService.swift` | 后台服务、watcher 管理、catch-up、reconcile |
| `Core/LocalRecords/FileSystemEventWatcher.swift` | FSEvents wrapper 与 JSONL path expansion |
| `Core/LocalRecords/LocalSourceImportQueue.swift` | 防抖、队列、单文件导入 |
| `Core/LocalRecords/LocalJSONLIncrementalReader.swift` | byte offset 增量读取完整行 |
| `Core/LocalRecords/LocalUsageScanner.swift` | 启动/手动 catch-up scan |
| `Database/LocalScanRepository.swift` | checkpoint、状态、key 去重、token_usages 写入 |

## 5. Checkpoint 模型

`local_scan_files` 当前保存：

```sql
source_tool TEXT NOT NULL,
path TEXT NOT NULL,
file_size INTEGER DEFAULT 0,
modified_at TEXT,
file_id TEXT,
read_offset INTEGER DEFAULT 0,
parse_context_json TEXT,
last_scanned_at TEXT,
imported_event_count INTEGER DEFAULT 0,
status TEXT NOT NULL,
last_error TEXT,
UNIQUE(source_tool, path)
```

关键点：

- 使用 `read_offset`，不是历史计划中的行号指针。
- `parse_context_json` 保存 adapter 的跨行元数据。
- 空 batch 也会推进 checkpoint。
- DB 写入失败时不推进 checkpoint。

## 6. 去重模型

`local_usage_imports` 是事件级幂等账本：

```sql
CREATE TABLE IF NOT EXISTS local_usage_imports (
  key TEXT PRIMARY KEY,
  source_tool TEXT NOT NULL,
  source_file TEXT NOT NULL,
  token_usage_id TEXT NOT NULL,
  imported_at TEXT NOT NULL
);
```

职责分离：

- `local_scan_files`：回答“这个文件读到哪里”。
- `local_usage_imports`：回答“这个 usage 事件是否已导入”。

`key` 由 adapter 生成：稳定 native id 优先；否则使用 canonical usage fingerprint。fingerprint 不包含 source_file、cwd、line number、raw prompt/response/tool output。

## 7. 错误处理

| 场景 | 当前处理 |
|---|---|
| root 不存在 | 跳过扫描，watcher 定期重试 |
| root/file 无权限 | source/file status 标记 `permission_denied` |
| JSON parse error | file/source status 标记 `parse_error`，不影响其他 source |
| 文件半行 | 等待下一次事件，不推进到半行之后 |
| 文件变小 | 从 0 重读，依赖 key 去重 |
| DB 失败 | transaction 回滚，不推进 checkpoint |

## 8. UI 行为

- Settings > Local Sources 展示 source status、root path、last scan。
- `Rescan Now` 调用 `LocalSourcesBackgroundService.rescanNow()`。
- 导入新 usage 后刷新 AppState。
- 菜单栏临时显示 live input/output token。

## 9. 测试覆盖

- `LocalJSONLIncrementalReaderTests`：offset、半行、truncate。
- `LocalScanRepositoryIncrementalTests`：checkpoint、事务回滚、状态。
- `LocalUsageScannerTests`：catch-up、not_found、parse_error 隔离。
- `FileSystemEventWatcherTests`：JSONL path expansion/dedupe。
- `ForkKeyTests`：文件/session 无关去重。
- `PrivacyLocalWatcherTests`：隐私约束。

## 10. 后续可改进

- Settings 展示文件级错误详情。
- Watcher 健康状态与最近事件时间。
- 自定义 source root。
- 更强的 root 权限授权引导。
