import XCTest
@testable import TokenLensApp

final class LocalUsageScannerTests: XCTestCase {
    func test_defaultAdapters_areCodexClaudeCodePiAndOpenCode() {
        let ids = LocalUsageScanner.defaultAdapters().map(\.id)
        XCTAssertEqual(ids, ["codex", "claude_code", "pi", "opencode"])
    }

    func test_scanAll_recordsNotFoundWithoutFailingOtherSources() async throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let missingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let foundRoot = try makeTempDirectory()
        let file = foundRoot.appendingPathComponent("ok.jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)
        let event = LocalUsageEvent(
            key: "pi:native:e1",
            sourceTool: "pi", sourceFile: file.path, sourceEventId: "e1", sourceSessionId: nil,
            sourceCwd: nil, timestamp: Date(), providerId: "anthropic", model: "claude",
            inputTokens: 1, outputTokens: 2, cacheReadTokens: 0, cacheWriteTokens: 0,
            reasoningTokens: 0, totalTokens: 3, costUsd: nil
        )
        let scanner = LocalUsageScanner(repository: repo, adapters: [
            StubLocalUsageAdapter(id: "codex", displayName: "Codex", root: missingRoot, files: [], parse: { _ in [] }),
            StubLocalUsageAdapter(id: "pi", displayName: "pi", root: foundRoot, files: [file], parse: { _ in [event] })
        ])

        await scanner.scanAll()

        let sources = try repo.fetchSources()
        // Non-existing root is not persisted by scan (handled later by watcher retry).
        XCTAssertNil(sources.first { $0.sourceTool == "codex" })
        XCTAssertEqual(sources.first { $0.sourceTool == "pi" }?.status, "ok")
        XCTAssertEqual(try TokenUsagesRepository(dbManager: dbManager).fetchRecent(limit: 10).count, 1)
    }

    func test_scanAll_marksParseErrorButContinuesOtherSources() async throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let badRoot = try makeTempDirectory()
        let goodRoot = try makeTempDirectory()
        let badFile = badRoot.appendingPathComponent("bad.jsonl")
        let goodFile = goodRoot.appendingPathComponent("good.jsonl")
        try "bad".write(to: badFile, atomically: true, encoding: .utf8)
        try "good".write(to: goodFile, atomically: true, encoding: .utf8)
        let event = LocalUsageEvent(
            key: "claude_code:native:good-1",
            sourceTool: "claude_code", sourceFile: goodFile.path, sourceEventId: "good-1", sourceSessionId: nil,
            sourceCwd: nil, timestamp: Date(), providerId: "anthropic", model: "claude",
            inputTokens: 5, outputTokens: 5, cacheReadTokens: 0, cacheWriteTokens: 0,
            reasoningTokens: 0, totalTokens: 10, costUsd: nil
        )
        let scanner = LocalUsageScanner(repository: repo, adapters: [
            StubLocalUsageAdapter(id: "codex", displayName: "Codex", root: badRoot, files: [badFile], parse: { _ in throw LocalUsageParseError.invalidJSON(line: 1) }),
            StubLocalUsageAdapter(id: "claude_code", displayName: "Claude Code", root: goodRoot, files: [goodFile], parse: { _ in [event] })
        ])

        await scanner.scanAll()

        let sources = try repo.fetchSources()
        XCTAssertEqual(sources.first { $0.sourceTool == "codex" }?.status, "parse_error")
        XCTAssertEqual(sources.first { $0.sourceTool == "claude_code" }?.status, "ok")
        XCTAssertEqual(try TokenUsagesRepository(dbManager: dbManager).fetchRecent(limit: 10).count, 1)
    }

    func test_scanAll_catchUpPersistsReadOffsetForWatcherResume() async throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("session.jsonl")
        let content = "{\"type\":\"usage\"}\n"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let event = LocalUsageEvent(
            key: "pi:native:offset-1",
            sourceTool: "pi", sourceFile: file.path, sourceEventId: "offset-1", sourceSessionId: nil,
            sourceCwd: nil, timestamp: Date(), providerId: "anthropic", model: "claude",
            inputTokens: 1, outputTokens: 2, cacheReadTokens: 0, cacheWriteTokens: 0,
            reasoningTokens: 0, totalTokens: 3, costUsd: nil
        )
        let scanner = LocalUsageScanner(repository: repo, adapters: [
            StubLocalUsageAdapter(id: "pi", displayName: "pi", root: root, files: [file], parse: { _ in [event] })
        ])

        await scanner.scanAll()

        let checkpoint = try XCTUnwrap(repo.checkpoint(for: "pi", path: file.path))
        XCTAssertEqual(checkpoint.readOffset, content.utf8.count)
        XCTAssertEqual(checkpoint.fileSize, content.utf8.count)
    }

    func test_scanAll_usesUnifiedAdapterSessionReadPath() async throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("session.any")
        try "not jsonl".write(to: file, atomically: true, encoding: .utf8)
        let adapter = SpySessionReadAdapter(root: root, file: file)
        let scanner = LocalUsageScanner(repository: repo, adapters: [adapter])

        await scanner.scanAll()

        XCTAssertEqual(adapter.readUsageChangesCallCount, 1)
        XCTAssertEqual(try TokenUsagesRepository(dbManager: dbManager).fetchRecent(limit: 10).count, 1)
    }

    func test_importQueue_usesUnifiedAdapterSessionReadPath() async throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("session.any")
        try "not jsonl".write(to: file, atomically: true, encoding: .utf8)
        let adapter = SpySessionReadAdapter(root: root, file: file)
        try repo.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: "spy",
            displayName: "Spy",
            rootPath: root.path,
            status: "watching",
            lastScanStartedAt: nil,
            lastScanFinishedAt: nil,
            filesSeen: 1,
            filesScanned: 0,
            eventsImported: 0,
            parseErrorCount: 0,
            lastError: nil
        ))
        let queue = LocalSourceImportQueue(repository: repo, adapters: [adapter], debounceInterval: 0)

        await queue.enqueue(sourceTool: "spy", records: [.appendOnlyJSONL(file)])
        await queue.flushNow()
        try await waitForUsageCount(dbManager: dbManager, expected: 1)

        XCTAssertEqual(adapter.readUsageChangesCallCount, 1)
    }

    func test_importQueue_deduplicatesRecordsByCheckpointPath() async throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let wal = root.appendingPathComponent("opencode.db-wal")
        try "db".write(to: db, atomically: true, encoding: .utf8)
        try "wal".write(to: wal, atomically: true, encoding: .utf8)
        let adapter = SpySessionReadAdapter(root: root, file: db)
        let dbRecord = LocalUsageRecord(readURL: db, checkpointURL: db, kind: .sqliteDatabase)
        let walTriggeredRecord = LocalUsageRecord(readURL: wal, checkpointURL: db, kind: .sqliteDatabase)
        try repo.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: "spy",
            displayName: "Spy",
            rootPath: root.path,
            status: "watching",
            lastScanStartedAt: nil,
            lastScanFinishedAt: nil,
            filesSeen: 1,
            filesScanned: 0,
            eventsImported: 0,
            parseErrorCount: 0,
            lastError: nil
        ))
        let queue = LocalSourceImportQueue(repository: repo, adapters: [adapter], debounceInterval: 0)

        await queue.enqueue(sourceTool: "spy", records: [dbRecord, walTriggeredRecord])
        await queue.flushNow()
        try await waitForUsageCount(dbManager: dbManager, expected: 1)

        XCTAssertEqual(adapter.readUsageChangesCallCount, 1)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLensTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForUsageCount(dbManager: DatabaseManager, expected: Int) async throws {
        let repository = TokenUsagesRepository(dbManager: dbManager)
        for _ in 0..<20 {
            if try repository.fetchRecent(limit: 10).count == expected {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(try repository.fetchRecent(limit: 10).count, expected)
    }
}

private struct StubLocalUsageAdapter: LocalUsageAdapter {
    let id: String
    let displayName: String
    let defaultRoot: URL
    let records: [LocalUsageRecord]
    let parseClosure: (LocalUsageRecord) throws -> [LocalUsageEvent]

    init(id: String, displayName: String, root: URL, files: [URL], parse: @escaping (URL) throws -> [LocalUsageEvent]) {
        self.id = id
        self.displayName = displayName
        self.defaultRoot = root
        self.records = files.map(LocalUsageRecord.appendOnlyJSONL)
        self.parseClosure = { record in try parse(record.readURL) }
    }

    func discoverRecords() throws -> [LocalUsageRecord] { records }

    func candidates(fromChangedPaths paths: [URL]) throws -> [LocalUsageRecord] {
        try LocalRecordJSON.candidateJSONLRecords(for: paths)
    }

    func readUsageChanges(record: LocalUsageRecord, checkpoint: LocalScanFileCheckpoint?) throws -> LocalUsageSessionReadResult {
        let events = try parseClosure(record)
        let attributes = try? FileManager.default.attributesOfItem(atPath: record.readURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return LocalUsageSessionReadResult(
            events: events,
            checkpoint: LocalScanFileCheckpointUpdate(
                sourceTool: id,
                path: record.checkpointURL.path,
                fileSize: fileSize,
                modifiedAt: attributes?[.modificationDate] as? Date,
                fileId: checkpoint?.fileId,
                readOffset: fileSize,
                parseContext: checkpoint?.parseContext,
                importedEventCount: events.count,
                status: "ok",
                lastError: nil
            ),
            observedSize: fileSize,
            shouldReenqueue: false
        )
    }
}

private final class SpySessionReadAdapter: LocalUsageAdapter {
    let id = "spy"
    let displayName = "Spy"
    let defaultRoot: URL
    let file: URL
    var readUsageChangesCallCount = 0

    init(root: URL, file: URL) {
        self.defaultRoot = root
        self.file = file
    }

    func discoverRecords() throws -> [LocalUsageRecord] {
        [.appendOnlyJSONL(file)]
    }

    func candidates(fromChangedPaths paths: [URL]) throws -> [LocalUsageRecord] {
        try LocalRecordJSON.candidateJSONLRecords(for: paths)
    }

    func readUsageChanges(record: LocalUsageRecord, checkpoint: LocalScanFileCheckpoint?) throws -> LocalUsageSessionReadResult {
        readUsageChangesCallCount += 1
        let event = LocalUsageEvent(
            key: "spy:native:event-1",
            sourceTool: "spy",
            sourceFile: record.readURL.path,
            sourceEventId: "event-1",
            sourceSessionId: "session-1",
            sourceCwd: nil,
            timestamp: Date(),
            providerId: "spy",
            model: "spy-model",
            inputTokens: 1,
            outputTokens: 2,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            reasoningTokens: 0,
            totalTokens: 3,
            costUsd: 0.01
        )
        return LocalUsageSessionReadResult(
            events: [event],
            checkpoint: LocalScanFileCheckpointUpdate(
                sourceTool: id,
                path: record.checkpointURL.path,
                fileSize: 8,
                modifiedAt: nil,
                fileId: nil,
                readOffset: 8,
                parseContext: nil,
                importedEventCount: 1,
                status: "ok",
                lastError: nil
            ),
            observedSize: 8,
            shouldReenqueue: false
        )
    }
}
