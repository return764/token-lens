import Foundation

/// Background service that watches built-in local session sources
/// and incrementally imports new usage data.
///
/// This class is NOT @MainActor — it manages its own dispatch queues.
/// Use `onRefreshNeeded` callback on the main actor for UI updates.
public final class LocalSourcesBackgroundService {
    private let repository: LocalScanRepository
    private let adapters: [any LocalUsageAdapter]
    private let importQueue: LocalSourceImportQueue
    private var watchers: [String: FileSystemEventWatcher] = [:]
    private let watcherLock = NSLock()
    private var reconcileTask: Task<Void, Never>?

    /// Retry interval for periodically checking root availability.
    private let retryInterval: TimeInterval = 30
    /// Safety net for missed/coalesced FSEvents: periodically enqueue changed files.
    private let reconcileInterval: TimeInterval = 30

    /// Callback invoked on the main actor after imports complete (for UI refresh).
    public var onRefreshNeeded: (() -> Void)?
    /// Callback invoked on the main actor with live token consumption data.
    /// Parameters: total input tokens, total output tokens, total cost (USD) of the newly imported batch.
    public var onLiveTokensImported: ((_ inputTokens: Int, _ outputTokens: Int, _ costUsd: Double) -> Void)?

    public init(
        repository: LocalScanRepository,
        adapters: [any LocalUsageAdapter] = LocalUsageScanner.defaultAdapters()
    ) {
        self.repository = repository
        self.adapters = adapters
        self.importQueue = LocalSourceImportQueue(repository: repository, adapters: adapters)
    }

    /// Start catch-up scan + watchers.
    public func start() async {
        print("[TokenLens] 🚀 LocalSourcesBackgroundService starting...")

        // Wire up import queue callback
        importQueue.onImportCompleted = { [weak self] sourceTool, result in
            guard let self else { return }
            DispatchQueue.main.async {
                if result.inserted > 0 {
                    tlog("📥 Import completed: [\(sourceTool)] inserted=\(result.inserted) in=\(result.inputTokens) out=\(result.outputTokens) cost=\(result.costUsd)")
                    self.onLiveTokensImported?(result.inputTokens, result.outputTokens, result.costUsd)
                }
                self.onRefreshNeeded?()
            }
        }

        // 1. Mark all existing-root sources as "scanning" simultaneously.
        let activeAdapters = adapters.filter {
            FileManager.default.fileExists(atPath: $0.defaultRoot.path)
        }
        for adapter in activeAdapters {
            try? repository.upsertSourceStatus(LocalScanSourceStatus(
                sourceTool: adapter.id,
                displayName: adapter.displayName,
                rootPath: adapter.defaultRoot.path,
                status: "scanning",
                lastScanStartedAt: Date(),
                lastScanFinishedAt: nil,
                filesSeen: 0,
                filesScanned: 0,
                eventsImported: 0,
                parseErrorCount: 0,
                lastError: nil
            ))
        }
        DispatchQueue.main.async { self.onRefreshNeeded?() }

        // 2. Scan all active sources concurrently, refresh UI as each finishes.
        print("[TokenLens] 📊 Running catch-up scan (\(activeAdapters.count) source(s))...")
        await withTaskGroup(of: Void.self) { group in
            for adapter in activeAdapters {
                group.addTask {
                    let scanner = LocalUsageScanner(repository: self.repository, adapters: [adapter])
                    await scanner.scan(adapter)
                    DispatchQueue.main.async { self.onRefreshNeeded?() }
                }
            }
        }
        print("[TokenLens] 📊 Catch-up scan complete")

        // 2. Start watchers for existing roots
        for adapter in adapters {
            startWatcher(for: adapter)
        }
        DispatchQueue.main.async { self.onRefreshNeeded?() }

        // 3. Safety net: FSEvents are hints, not the source of truth.
        startPeriodicReconcile()
    }

    /// Stop all watchers.
    public func stop() {
        watcherLock.lock()
        defer { watcherLock.unlock() }
        reconcileTask?.cancel()
        reconcileTask = nil
        for (_, watcher) in watchers {
            watcher.stop()
        }
        watchers.removeAll()
    }

    /// Force a full rescan (re-runs catch-up scan + re-establishes watchers).
    public func rescanNow() async {
        print("[TokenLens] 🔄 Rescan requested...")
        stop()
        await start()
    }

    // MARK: - Watcher management

    private func startWatcher(for adapter: any LocalUsageAdapter) {
        let root = adapter.defaultRoot

        guard FileManager.default.fileExists(atPath: root.path) else {
            print("[TokenLens] ⚠️ [\(adapter.id)] Root not found: \(root.path) — will retry in \(retryInterval)s")
            scheduleRetry(for: adapter)
            return
        }

        print("[TokenLens] 🟢 [\(adapter.id)] Starting watcher → \(root.path)")

        let watcher = FileSystemEventWatcher(root: root) { [weak self] paths in
            guard let self else { return }
            Task {
                do {
                    let candidates = try adapter.candidates(fromChangedPaths: paths)
                    await self.importQueue.enqueue(sourceTool: adapter.id, records: candidates)
                } catch {
                    print("[TokenLens] ⚠️ [\(adapter.id)] Candidate normalization failed: \(error)")
                }
            }
        }

        do {
            try watcher.start()
            watcherLock.lock()
            watchers[adapter.id] = watcher
            watcherLock.unlock()

            try markSourceWatching(adapter: adapter, rootPath: root.path)
        } catch {
            print("[TokenLens] ❌ [\(adapter.id)] Watcher start failed: \(error.localizedDescription)")
            try? repository.upsertSourceStatus(LocalScanSourceStatus(
                sourceTool: adapter.id,
                displayName: adapter.displayName,
                rootPath: root.path,
                status: "permission_denied",
                lastScanStartedAt: nil,
                lastScanFinishedAt: nil,
                filesSeen: 0,
                filesScanned: 0,
                eventsImported: 0,
                parseErrorCount: 0,
                lastError: error.localizedDescription
            ))
            scheduleRetry(for: adapter)
        }
    }

    private func startPeriodicReconcile() {
        reconcileTask?.cancel()
        let interval = reconcileInterval
        reconcileTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.enqueueChangedFilesFromReconcile()
            }
        }
    }

    private func enqueueChangedFilesFromReconcile() async {
        for adapter in adapters {
            guard FileManager.default.fileExists(atPath: adapter.defaultRoot.path) else { continue }
            do {
                let records = try adapter.discoverRecords()
                let changed = records.filter { record in
                    record.kind == .sqliteDatabase || ((try? repository.shouldScanFile(sourceTool: adapter.id, url: record.checkpointURL)) ?? true)
                }
                guard !changed.isEmpty else { continue }
                print("[TokenLens] 🧹 [\(adapter.id)] Reconcile enqueuing \(changed.count) changed record(s)")
                await importQueue.enqueue(sourceTool: adapter.id, records: changed)
            } catch {
                print("[TokenLens] ⚠️ [\(adapter.id)] Reconcile failed: \(error)")
            }
        }
    }

    private func markSourceWatching(adapter: any LocalUsageAdapter, rootPath: String) throws {
        let existing = try repository.fetchSources().first { $0.sourceTool == adapter.id }
        try repository.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: adapter.id,
            displayName: adapter.displayName,
            rootPath: rootPath,
            status: "watching",
            lastScanStartedAt: existing?.lastScanStartedAt,
            lastScanFinishedAt: existing?.lastScanFinishedAt,
            filesSeen: existing?.filesSeen ?? 0,
            filesScanned: existing?.filesScanned ?? 0,
            eventsImported: existing?.eventsImported ?? 0,
            parseErrorCount: existing?.parseErrorCount ?? 0,
            lastError: nil
        ))
    }

    private func scheduleRetry(for adapter: any LocalUsageAdapter) {
        let interval = retryInterval
        let adapterId = adapter.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if !Task.isCancelled {
                print("[TokenLens] 🔁 [\(adapterId)] Retrying watcher setup...")
                self?.startWatcher(for: adapter)
            }
        }
    }
}
