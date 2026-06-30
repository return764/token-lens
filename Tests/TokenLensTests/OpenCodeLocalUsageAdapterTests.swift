import GRDB
import XCTest
@testable import TokenLensApp

final class OpenCodeLocalUsageAdapterTests: XCTestCase {
    func test_readSessionChanges_importsInitialUsageAggregate() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        try makeOpenCodeDatabase(db)
        try insertSession(
            db,
            id: "sess-1",
            directory: "/Users/example/project",
            model: #"{"providerID":"anthropic","id":"claude-sonnet-4-20250514"}"#,
            input: 100,
            output: 40,
            reasoning: 7,
            cacheRead: 11,
            cacheWrite: 3,
            cost: 0.123,
            timeCreated: 1_766_000_000_000,
            timeUpdated: 1_766_000_001_000
        )

        let result = try OpenCodeLocalUsageAdapter(root: root).readSessionChanges(file: db, checkpoint: nil)

        XCTAssertEqual(result.events.count, 1)
        let event = try XCTUnwrap(result.events.first)
        XCTAssertEqual(event.sourceTool, "opencode")
        XCTAssertEqual(event.sourceSessionId, "sess-1")
        XCTAssertEqual(event.sourceCwd, "/Users/example/project")
        XCTAssertEqual(event.providerId, "anthropic")
        XCTAssertEqual(event.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(event.inputTokens, 100)
        XCTAssertEqual(event.outputTokens, 40)
        XCTAssertEqual(event.reasoningTokens, 7)
        XCTAssertEqual(event.cacheReadTokens, 11)
        XCTAssertEqual(event.cacheWriteTokens, 3)
        XCTAssertEqual(event.totalTokens, 161)
        XCTAssertEqual(try XCTUnwrap(event.costUsd), 0.123, accuracy: 0.000001)
        XCTAssertTrue(event.key.hasPrefix("opencode:native:session:sess-1:updated:1766000001000:"))
        XCTAssertNotNil(result.checkpoint.parseContext)
    }

    func test_readSessionChanges_skipsUnchangedAggregate() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        try makeOpenCodeDatabase(db)
        try insertSession(db, id: "sess-1", input: 10, output: 5, cost: 0.01)
        let adapter = OpenCodeLocalUsageAdapter(root: root)
        let first = try adapter.readSessionChanges(file: db, checkpoint: nil)
        let checkpoint = LocalScanFileCheckpoint(
            sourceTool: "opencode",
            path: db.path,
            fileSize: first.checkpoint.fileSize,
            modifiedAt: first.checkpoint.modifiedAt,
            fileId: nil,
            readOffset: first.checkpoint.readOffset,
            lastScannedAt: nil,
            parseContext: first.checkpoint.parseContext
        )

        let second = try adapter.readSessionChanges(file: db, checkpoint: checkpoint)

        XCTAssertEqual(second.events, [])
    }

    func test_readSessionChanges_importsOnlyPositiveDelta() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        try makeOpenCodeDatabase(db)
        try insertSession(db, id: "sess-1", input: 10, output: 5, cacheRead: 1, cost: 0.01, timeUpdated: 1000)
        let adapter = OpenCodeLocalUsageAdapter(root: root)
        let first = try adapter.readSessionChanges(file: db, checkpoint: nil)
        try updateSession(db, id: "sess-1", input: 25, output: 9, cacheRead: 3, cost: 0.025, timeUpdated: 2000)
        let checkpoint = checkpoint(from: first, path: db.path)

        let second = try adapter.readSessionChanges(file: db, checkpoint: checkpoint)

        let event = try XCTUnwrap(second.events.first)
        XCTAssertEqual(second.events.count, 1)
        XCTAssertEqual(event.inputTokens, 15)
        XCTAssertEqual(event.outputTokens, 4)
        XCTAssertEqual(event.cacheReadTokens, 2)
        XCTAssertEqual(event.totalTokens, 21)
        XCTAssertEqual(try XCTUnwrap(event.costUsd), 0.015, accuracy: 0.000001)
    }

    func test_readSessionChanges_treatsAggregateDecreaseAsReset() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        try makeOpenCodeDatabase(db)
        try insertSession(db, id: "sess-1", input: 100, output: 50, cost: 0.10, timeUpdated: 1000)
        let adapter = OpenCodeLocalUsageAdapter(root: root)
        let first = try adapter.readSessionChanges(file: db, checkpoint: nil)
        try updateSession(db, id: "sess-1", input: 8, output: 4, cost: 0.02, timeUpdated: 2000)

        let reset = try adapter.readSessionChanges(file: db, checkpoint: checkpoint(from: first, path: db.path))

        let event = try XCTUnwrap(reset.events.first)
        XCTAssertEqual(event.inputTokens, 8)
        XCTAssertEqual(event.outputTokens, 4)
        XCTAssertEqual(event.totalTokens, 12)
        XCTAssertEqual(try XCTUnwrap(event.costUsd), 0.02, accuracy: 0.000001)
    }

    func test_readSessionChanges_reportsUnsupportedSchema() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let queue = try DatabaseQueue(path: db.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE session (id TEXT PRIMARY KEY)")
        }

        XCTAssertThrowsError(try OpenCodeLocalUsageAdapter(root: root).readSessionChanges(file: db, checkpoint: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("Unsupported OpenCode session schema"))
        }
    }

    func test_readSessionChanges_doesNotExposeSensitiveTablesInEventOrContext() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        try makeOpenCodeDatabase(db, includeSensitiveTables: true)
        try insertSession(db, id: "sess-1", directory: "/safe/project", input: 10, output: 5, cost: 0.01)

        let result = try OpenCodeLocalUsageAdapter(root: root).readSessionChanges(file: db, checkpoint: nil)

        let event = try XCTUnwrap(result.events.first)
        XCTAssertFalse(event.sourceEventId.contains("SECRET_PROMPT"))
        XCTAssertFalse(event.sourceCwd?.contains("SECRET_PROMPT") ?? false)
        XCTAssertFalse(result.checkpoint.parseContext?.json.contains("SECRET_PROMPT") ?? false)
        XCTAssertFalse(result.checkpoint.parseContext?.json.contains("SECRET_API_KEY") ?? false)
    }

    func test_candidates_normalizeDatabaseSidecarChanges() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        try makeOpenCodeDatabase(db)
        let adapter = OpenCodeLocalUsageAdapter(root: root)

        let candidates = try adapter.candidates(fromChangedPaths: [
            root.appendingPathComponent("opencode.db-wal"),
            root.appendingPathComponent("opencode.db-shm"),
            root
        ])

        XCTAssertEqual(candidates, [db.resolvingSymlinksInPath()])
    }

    func test_discoverFiles_includesDatabaseAndExistingSidecars() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let wal = root.appendingPathComponent("opencode.db-wal")
        try makeOpenCodeDatabase(db)
        try Data().write(to: wal)
        let adapter = OpenCodeLocalUsageAdapter(root: root)

        let files = try adapter.discoverFiles()

        XCTAssertEqual(files, [
            db.resolvingSymlinksInPath(),
            wal.resolvingSymlinksInPath()
        ])
    }

    func test_candidates_keepWalOnlyChangeAsWalTrigger() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let wal = root.appendingPathComponent("opencode.db-wal")
        try makeOpenCodeDatabase(db)
        try Data().write(to: wal)
        let adapter = OpenCodeLocalUsageAdapter(root: root)

        let candidates = try adapter.candidates(fromChangedPaths: [wal])

        XCTAssertEqual(candidates, [wal.resolvingSymlinksInPath()])
    }

    func test_readSessionChanges_queriesDatabaseWhenSidecarIsPassed() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let wal = root.appendingPathComponent("opencode.db-wal")
        try makeOpenCodeDatabase(db)
        try Data().write(to: wal)
        try insertSession(db, id: "sess-1", input: 10, output: 5, cost: 0.01)

        let result = try OpenCodeLocalUsageAdapter(root: root).readSessionChanges(file: wal, checkpoint: nil)

        let event = try XCTUnwrap(result.events.first)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(event.sourceFile, db.resolvingSymlinksInPath().path)
        XCTAssertEqual(result.checkpoint.path, db.resolvingSymlinksInPath().path)
    }

    func test_readSessionChanges_readsUncheckpointedWalDataThroughDatabase() throws {
        let root = try makeTempDirectory()
        let db = root.appendingPathComponent("opencode.db")
        let wal = root.appendingPathComponent("opencode.db-wal")
        try makeOpenCodeDatabase(db)
        let writer = try DatabaseQueue(path: db.path)
        try writer.writeWithoutTransaction { db in
            _ = try String.fetchOne(db, sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
        }
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO session
                (id, directory, model, cost, tokens_input, tokens_output, tokens_reasoning,
                 tokens_cache_read, tokens_cache_write, time_created, time_updated)
                VALUES ('sess-wal', '/project', '{"providerID":"openai","id":"gpt-5"}',
                        0.02, 12, 8, 0, 0, 0, 1000, 2000)
                """)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: wal.path))

        let result = try OpenCodeLocalUsageAdapter(root: root).readSessionChanges(file: wal, checkpoint: nil)

        let event = try XCTUnwrap(result.events.first)
        XCTAssertEqual(event.sourceSessionId, "sess-wal")
        XCTAssertEqual(event.inputTokens, 12)
        XCTAssertEqual(event.outputTokens, 8)
        XCTAssertEqual(event.sourceFile, db.resolvingSymlinksInPath().path)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLensTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeOpenCodeDatabase(_ url: URL, includeSensitiveTables: Bool = false) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE session (
                  id TEXT PRIMARY KEY,
                  directory TEXT NOT NULL,
                  model TEXT,
                  cost REAL DEFAULT 0 NOT NULL,
                  tokens_input INTEGER DEFAULT 0 NOT NULL,
                  tokens_output INTEGER DEFAULT 0 NOT NULL,
                  tokens_reasoning INTEGER DEFAULT 0 NOT NULL,
                  tokens_cache_read INTEGER DEFAULT 0 NOT NULL,
                  tokens_cache_write INTEGER DEFAULT 0 NOT NULL,
                  time_created INTEGER NOT NULL,
                  time_updated INTEGER NOT NULL
                )
                """)
            if includeSensitiveTables {
                try db.execute(sql: "CREATE TABLE message (id TEXT PRIMARY KEY, data TEXT NOT NULL)")
                try db.execute(sql: "CREATE TABLE account (id TEXT PRIMARY KEY, data TEXT NOT NULL)")
                try db.execute(sql: "INSERT INTO message (id, data) VALUES ('m1', 'SECRET_PROMPT')")
                try db.execute(sql: "INSERT INTO account (id, data) VALUES ('a1', 'SECRET_API_KEY')")
            }
        }
    }

    private func insertSession(
        _ url: URL,
        id: String,
        directory: String = "/project",
        model: String? = #"{"providerID":"openai","id":"gpt-5"}"#,
        input: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        cost: Double = 0,
        timeCreated: Int64 = 1000,
        timeUpdated: Int64 = 1000
    ) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO session
                (id, directory, model, cost, tokens_input, tokens_output, tokens_reasoning,
                 tokens_cache_read, tokens_cache_write, time_created, time_updated)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    id, directory, model, cost, input, output, reasoning,
                    cacheRead, cacheWrite, timeCreated, timeUpdated
                ])
        }
    }

    private func updateSession(
        _ url: URL,
        id: String,
        input: Int,
        output: Int,
        reasoning: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        cost: Double,
        timeUpdated: Int64
    ) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                UPDATE session
                SET tokens_input = ?, tokens_output = ?, tokens_reasoning = ?,
                    tokens_cache_read = ?, tokens_cache_write = ?, cost = ?, time_updated = ?
                WHERE id = ?
                """, arguments: [input, output, reasoning, cacheRead, cacheWrite, cost, timeUpdated, id])
        }
    }

    private func checkpoint(from result: LocalUsageSessionReadResult, path: String) -> LocalScanFileCheckpoint {
        LocalScanFileCheckpoint(
            sourceTool: "opencode",
            path: path,
            fileSize: result.checkpoint.fileSize,
            modifiedAt: result.checkpoint.modifiedAt,
            fileId: nil,
            readOffset: result.checkpoint.readOffset,
            lastScannedAt: nil,
            parseContext: result.checkpoint.parseContext
        )
    }
}
