import Foundation

/// Serial import queue that debounces and deduplicates file-system events.
/// Only one import runs per (sourceTool, path) at a time.
public actor LocalSourceImportQueue {
    private let repository: LocalScanRepository
    private let adapters: [any LocalUsageAdapter]
    private let reader = LocalJSONLIncrementalReader()
    private let debounceInterval: TimeInterval

    private var pending: Set<String> = []   // keyed by "tool::path"
    private var inProgress: Set<String> = []
    private var pendingFlush = false

    /// Callback invoked after every import batch completes (for UI refresh).
    /// Parameters: sourceTool, ImportResult (includes token totals for live display).
    public nonisolated(unsafe) var onImportCompleted: ((String, ImportResult) -> Void)?

    public init(
        repository: LocalScanRepository,
        adapters: [any LocalUsageAdapter],
        debounceInterval: TimeInterval = 0.5
    ) {
        self.repository = repository
        self.adapters = adapters
        self.debounceInterval = debounceInterval
    }

    /// Enqueue a set of file paths affected by filesystem events.
    public func enqueue(sourceTool: String, paths: [URL]) {
        var added = 0
        for path in paths {
            let key = "\(sourceTool)::\(path.path)"
            let wasPending = pending.contains(key)
            pending.insert(key)
            if !wasPending { added += 1 }
        }
        if added > 0 {
            let names = paths.map { $0.lastPathComponent }.joined(separator: ", ")
            print("[TokenLens] 📥 Enqueued \(added) file(s) from [\(sourceTool)]: \(names)")
        }
        if !pending.isEmpty {
            scheduleFlush()
        }
    }

    /// Force an immediate flush (e.g. rescanNow).
    public func flushNow() {
        pendingFlush = true
        processPending()
    }

    // MARK: - Private

    private func scheduleFlush() {
        guard !pendingFlush else { return }
        pendingFlush = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            processPending()
        }
    }

    private func processPending() {
        guard pendingFlush else { return }
        pendingFlush = false

        let batch = pending.filter { !inProgress.contains($0) }
        pending.subtract(batch)

        guard !batch.isEmpty else { return }

        for key in batch {
            let parts = key.components(separatedBy: "::")
            guard parts.count >= 2 else { continue }
            let sourceTool = parts[0]
            let path = URL(fileURLWithPath: parts.dropFirst().joined(separator: "::"))
            inProgress.insert(key)

            Task {
                defer { Task { self.finishImport(key: key) } }
                await importFile(sourceTool: sourceTool, path: path)
            }
        }
    }

    private func importFile(sourceTool: String, path: URL) async {
        guard let adapter = adapters.first(where: { $0.id == sourceTool }) else { return }

        do {
            let checkpoint = try repository.checkpoint(for: sourceTool, path: path.path)
            let readOffset = Int64(checkpoint?.readOffset ?? 0)
            let batch = try reader.readNewLines(url: path, from: readOffset)

            guard !batch.lines.isEmpty else {
                print("[TokenLens] 📄 [\(sourceTool)] \(path.lastPathComponent): no new lines (offset=\(readOffset), size=\(batch.fileSize))")
                _ = try repository.importIncrementalUsageEvents([], checkpoint: LocalScanFileCheckpointUpdate(
                    sourceTool: sourceTool, path: path.path,
                    fileSize: Int(batch.fileSize), modifiedAt: batch.modifiedAt,
                    fileId: checkpoint?.fileId, readOffset: Int(batch.nextOffset),
                    parseContext: checkpoint?.parseContext,
                    importedEventCount: 0, status: "ok", lastError: nil
                ))
                return
            }

            print("[TokenLens] 📖 [\(sourceTool)] \(path.lastPathComponent): reading \(batch.lines.count) new line(s) (offset \(readOffset)→\(batch.nextOffset), size=\(batch.fileSize))")

            var parseContext = try adapter.bootstrapContext(file: path, checkpoint: checkpoint)
            let events = try adapter.parseLines(batch.lines, file: path, context: &parseContext)
            let checkpointFileSize = Int(batch.fileSize)
            let checkpointModifiedAt = batch.modifiedAt
            let checkpointReadOffset = Int(batch.nextOffset)

            let result = try repository.importIncrementalUsageEvents(events, checkpoint: LocalScanFileCheckpointUpdate(
                sourceTool: sourceTool, path: path.path,
                fileSize: checkpointFileSize, modifiedAt: checkpointModifiedAt,
                fileId: checkpoint?.fileId, readOffset: checkpointReadOffset,
                parseContext: parseContext,
                importedEventCount: events.count, status: "ok", lastError: nil
            ))

            if result.inserted > 0 {
                print("[TokenLens] ✅ [\(sourceTool)] Imported \(result.inserted) usage event(s) from \(path.lastPathComponent) (skipped \(result.skipped))")
            } else {
                print("[TokenLens] ⏭️  [\(sourceTool)] \(path.lastPathComponent): \(events.count) event(s) parsed, all \(result.skipped) skipped (already imported)")
            }

            try updateSourceStats(sourceTool: sourceTool, filesScanned: 1, eventsImported: result.inserted)
            onImportCompleted?(sourceTool, result)

            // Keep draining: if the file has grown again since we started, re-enqueue.
            // This handles the case where the writer appends data faster than FSEvents
            // can deliver events (or events are coalesced / dropped).
            let currentSize = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? NSNumber)?.int64Value ?? 0
            if currentSize > Int64(checkpointReadOffset) {
                print("[TokenLens] 🔁 [\(sourceTool)] \(path.lastPathComponent): file grew from offset \(checkpointReadOffset) to \(currentSize) during import — re-enqueuing")
                enqueue(sourceTool: sourceTool, paths: [path])
            }
        } catch {
            print("[TokenLens] ❌ [\(sourceTool)] Import error \(path.lastPathComponent): \(error)")
            let ck = try? repository.checkpoint(for: sourceTool, path: path.path)
            _ = try? repository.importIncrementalUsageEvents([], checkpoint: LocalScanFileCheckpointUpdate(
                sourceTool: sourceTool, path: path.path,
                fileSize: 0, modifiedAt: nil,
                fileId: ck?.fileId, readOffset: ck?.readOffset ?? 0,
                parseContext: ck?.parseContext,
                importedEventCount: 0, status: "parse_error", lastError: String(describing: error)
            ))
        }
    }

    private func finishImport(key: String) {
        inProgress.remove(key)
        if pending.contains(key) {
            scheduleFlush()
        }
    }

    private func updateSourceStats(sourceTool: String, filesScanned: Int, eventsImported: Int) throws {
        let sources = try repository.fetchSources()
        guard let source = sources.first(where: { $0.sourceTool == sourceTool }) else { return }
        try repository.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: sourceTool,
            displayName: source.displayName,
            rootPath: source.rootPath,
            status: source.status,
            lastScanStartedAt: source.lastScanStartedAt,
            lastScanFinishedAt: Date(),
            filesSeen: source.filesSeen,
            filesScanned: source.filesScanned + filesScanned,
            eventsImported: source.eventsImported + eventsImported,
            parseErrorCount: source.parseErrorCount,
            lastError: nil
        ))
    }
}
