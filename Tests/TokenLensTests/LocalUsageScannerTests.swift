import XCTest
@testable import TokenLensApp

final class LocalUsageScannerTests: XCTestCase {
    func test_defaultAdapters_areCodexClaudeCodeAndPi() {
        let ids = LocalUsageScanner.defaultAdapters().map(\.id)
        XCTAssertEqual(ids, ["codex", "claude_code", "pi"])
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

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLensTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct StubLocalUsageAdapter: LocalUsageAdapter {
    let id: String
    let displayName: String
    let defaultRoot: URL
    let files: [URL]
    let parseClosure: (URL) throws -> [LocalUsageEvent]

    init(id: String, displayName: String, root: URL, files: [URL], parse: @escaping (URL) throws -> [LocalUsageEvent]) {
        self.id = id
        self.displayName = displayName
        self.defaultRoot = root
        self.files = files
        self.parseClosure = parse
    }

    func discoverFiles() throws -> [URL] { files }
    func parseFile(_ url: URL) throws -> [LocalUsageEvent] { try parseClosure(url) }
    func parseLines(_ lines: [(lineNumber: Int?, text: String)], file: URL, context: inout LocalUsageParseContext?) throws -> [LocalUsageEvent] { try parseClosure(file) }
}
