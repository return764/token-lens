import Foundation

public final class LocalUsageScanner {
    private let repository: LocalScanRepository
    private let adapters: [any LocalUsageAdapter]

    public init(repository: LocalScanRepository, adapters: [any LocalUsageAdapter] = LocalUsageScanner.defaultAdapters()) {
        self.repository = repository
        self.adapters = adapters
    }

    public static func defaultAdapters() -> [any LocalUsageAdapter] {
        [
            CodexLocalUsageAdapter(),
            ClaudeCodeLocalUsageAdapter(),
            PiLocalUsageAdapter(),
            OpenCodeLocalUsageAdapter(),
        ]
    }

    public func scanAll() async {
        for adapter in adapters {
            await scan(adapter)
        }
    }

    public func scan(_ adapter: any LocalUsageAdapter) async {
        let startedAt = Date()

        guard FileManager.default.fileExists(atPath: adapter.defaultRoot.path) else {
            // Root doesn't exist yet — skip scan, watcher will retry.
            return
        }

        do {
            try repository.upsertSourceStatus(LocalScanSourceStatus(
                sourceTool: adapter.id,
                displayName: adapter.displayName,
                rootPath: adapter.defaultRoot.path,
                status: "scanning",
                lastScanStartedAt: startedAt,
                lastScanFinishedAt: nil,
                filesSeen: 0,
                filesScanned: 0,
                eventsImported: 0,
                parseErrorCount: 0,
                lastError: nil
            ))

            let records = try adapter.discoverRecords()
            var filesScanned = 0
            var eventsImported = 0
            var parseErrorCount = 0
            var lastError: String?

            for record in records {
                guard record.kind == .sqliteDatabase || ((try? repository.shouldScanFile(sourceTool: adapter.id, url: record.checkpointURL)) ?? true) else { continue }
                filesScanned += 1
                let attributes = try? FileManager.default.attributesOfItem(atPath: record.readURL.path)
                let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                let modifiedAt = attributes?[.modificationDate] as? Date

                do {
                    let existingCheckpoint = try repository.checkpoint(for: adapter.id, path: record.checkpointURL.path)
                    let readResult = try adapter.readUsageChanges(record: record, checkpoint: existingCheckpoint)

                    let result = try repository.importIncrementalUsageEvents(readResult.events, checkpoint: readResult.checkpoint)
                    eventsImported += result.inserted
                } catch {
                    parseErrorCount += 1
                    lastError = sanitize(error)
                    try? repository.upsertFileStatus(LocalScanFileStatus(
                        sourceTool: adapter.id,
                        path: record.checkpointURL.path,
                        fileSize: fileSize,
                        modifiedAt: modifiedAt,
                        lastScannedAt: Date(),
                        importedEventCount: 0,
                        status: classifyFileError(error),
                        lastError: lastError
                    ))
                }
            }

            try repository.upsertSourceStatus(LocalScanSourceStatus(
                sourceTool: adapter.id,
                displayName: adapter.displayName,
                rootPath: adapter.defaultRoot.path,
                status: parseErrorCount > 0 ? "parse_error" : "ok",
                lastScanStartedAt: startedAt,
                lastScanFinishedAt: Date(),
                filesSeen: records.count,
                filesScanned: filesScanned,
                eventsImported: eventsImported,
                parseErrorCount: parseErrorCount,
                lastError: lastError
            ))
        } catch {
            try? repository.upsertSourceStatus(LocalScanSourceStatus(
                sourceTool: adapter.id,
                displayName: adapter.displayName,
                rootPath: adapter.defaultRoot.path,
                status: classifySourceError(error),
                lastScanStartedAt: startedAt,
                lastScanFinishedAt: Date(),
                filesSeen: 0,
                filesScanned: 0,
                eventsImported: 0,
                parseErrorCount: 0,
                lastError: sanitize(error)
            ))
        }
    }

    private func classifySourceError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
            return "permission_denied"
        }
        return "parse_error"
    }

    private func classifyFileError(_ error: Error) -> String {
        classifySourceError(error) == "permission_denied" ? "permission_denied" : "parse_error"
    }

    private func sanitize(_ error: Error) -> String {
        let text = String(describing: error)
        return text.count > 300 ? String(text.prefix(300)) : text
    }
}
