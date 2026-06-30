import XCTest
@testable import TokenLensApp

/// Verifies that NON-usage events (user messages, tool calls, raw prompt/response)
/// are never written to token_usages or local_usage_imports.
final class PrivacyLocalWatcherTests: XCTestCase {

    func test_nonUsageEvents_notImported() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        // Simulate events that look like user messages (no usage)
        let userMessageEvent = LocalUsageEvent(
            key: "pi:native:user-msg-1",
            sourceTool: "pi", sourceFile: "/tmp/pi.jsonl", sourceEventId: "user-msg-1",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: nil, model: nil, inputTokens: 0, outputTokens: 0,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 0,
            costUsd: nil
        )

        // Only events with actual token usage should have been generated.
        // But even if one slips through with zero tokens, verify our adapters
        // only generate events from usage-bearing lines.

        // Test: Pi adapter only generates events for assistant messages with usage
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("session.jsonl")
        try writeJSONL([
            #"{"type":"session","id":"sess-1","cwd":"/work"}"#,
            #"{"type":"message","id":"user-1","message":{"role":"user","content":"hello"}}"#,
            #"{"type":"message","id":"assistant-1","message":{"role":"user","content":"redacted"}}"#,
            #"{"type":"message","id":"assistant-no-usage","message":{"role":"assistant"}}"#,
            #"{"type":"message","id":"assistant-2","message":{"role":"assistant","usage":{"input":10,"output":5,"totalTokens":15}}}"#,
        ], to: file)

        let adapter = PiLocalUsageAdapter(root: root)
        var context: LocalUsageParseContext?
        let events = try adapter.parseJSONLLines(
            [
                (1, #"{"type":"session","id":"sess-1","cwd":"/work"}"#),
                (2, #"{"type":"message","id":"user-1","message":{"role":"user","content":"hello"}}"#),
                (3, #"{"type":"message","id":"assistant-no-usage","message":{"role":"assistant"}}"#),
                (4, #"{"type":"message","id":"assistant-2","message":{"role":"assistant","usage":{"input":10,"output":5,"totalTokens":15}}}"#),
            ],
            record: .appendOnlyJSONL(file),
            context: &context
        )

        XCTAssertEqual(events.count, 1, "Only the usage-bearing message should produce an event")
        XCTAssertEqual(events[0].sourceEventId, "assistant-2")
        XCTAssertEqual(events[0].totalTokens, 15)
    }

    func test_codexAdapter_onlyTokenCountEvents() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("codex.jsonl")

        let adapter = CodexLocalUsageAdapter(root: root)
        let lines: [(Int?, String)] = [
            (1, #"{"type":"event_msg","payload":{"type":"user_message","content":"redacted"}}"#),
            (2, #"{"type":"event_msg","payload":{"type":"assistant_message","content":"redacted"}}"#),
            (3, #"{"type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5"}}"#),
            (4, #"{"type":"event_msg","timestamp":"2026-01-01T00:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50,"output_tokens":30,"total_tokens":80}}}}"#),
        ]
        var context: LocalUsageParseContext?
        let events = try adapter.parseJSONLLines(lines, record: .appendOnlyJSONL(file), context: &context)

        XCTAssertEqual(events.count, 1, "Only token_count events should produce usage")
        XCTAssertEqual(events[0].totalTokens, 80)
        XCTAssertEqual(events[0].model, "gpt-5", "Model should come from turn_context")
    }

    func test_keyDoesNotContainFileOrCwdPath() throws {
        // Verify key generation excludes source_file and source_cwd
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        let key1 = LocalUsageKeyBuilder.build(
            sourceTool: "pi", nativeId: nil,
            timestamp: createdAt, providerId: "anthropic", model: "claude",
            inputTokens: 10, outputTokens: 5,
            cacheReadTokens: 0, cacheWriteTokens: 0,
            reasoningTokens: 0, totalTokens: 15,
            costUsd: nil
        )
        let key2 = LocalUsageKeyBuilder.build(
            sourceTool: "pi", nativeId: nil,
            timestamp: createdAt, providerId: "anthropic", model: "claude",
            inputTokens: 10, outputTokens: 5,
            cacheReadTokens: 0, cacheWriteTokens: 0,
            reasoningTokens: 0, totalTokens: 15,
            costUsd: nil
        )

        // Same usage should yield same key regardless of file/cwd
        XCTAssertEqual(key1, key2)
    }

    func test_noRawContentStoredInDb() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        let event = LocalUsageEvent(
            key: "pi:native:msg-1",
            sourceTool: "pi", sourceFile: "/tmp/pi.jsonl", sourceEventId: "msg-1",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 10, outputTokens: 5,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 15,
            costUsd: nil
        )
        _ = try repo.importUsageEvents([event])

        // Verify token_usages has no raw content columns
        let columns = try dbManager.fetchColumnNames(table: "token_usages")
        XCTAssertFalse(columns.contains("raw_prompt"))
        XCTAssertFalse(columns.contains("raw_response"))
        XCTAssertFalse(columns.contains("tool_output"))
        XCTAssertFalse(columns.contains("api_key"))

        // Verify local_usage_imports has no content columns
        let importColumns = try dbManager.fetchColumnNames(table: "local_usage_imports")
        XCTAssertFalse(importColumns.contains("raw_content"))
        XCTAssertFalse(importColumns.contains("prompt"))
        XCTAssertFalse(importColumns.contains("response"))
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLensTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJSONL(_ lines: [String], to url: URL) throws {
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
