import XCTest
@testable import TokenLensApp

final class CodexLocalUsageAdapterTests: XCTestCase {
    func test_readUsageChanges_importsLastTokenUsageWithoutCumulativeDoubleCount() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("codex.jsonl")
        try writeJSONL([
            #"{"type":"session_meta","payload":{"id":"codex-session","cwd":"/Users/example/work","model_provider":"openai"}}"#,
            #"{"type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5-codex","cwd":"/Users/example/work"}}"#,
            #"{"type":"event_msg","timestamp":"2026-06-09T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":40,"cached_input_tokens":15,"reasoning_output_tokens":7,"total_tokens":162},"total_token_usage":{"input_tokens":9999,"output_tokens":9999,"total_tokens":19998}}}}"#
        ], to: file)

        let adapter = CodexLocalUsageAdapter(root: root)
        let events = try adapter.readUsageChanges(record: .appendOnlyJSONL(file), checkpoint: nil).events

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        // Codex event has no stable id, uses usage fingerprint hash
        XCTAssertTrue(event.key.hasPrefix("codex:usage:"))
        XCTAssertEqual(event.sourceTool, "codex")
        XCTAssertEqual(event.sourceSessionId, "codex-session")
        XCTAssertEqual(event.sourceCwd, "/Users/example/work")
        XCTAssertEqual(event.providerId, "openai")
        XCTAssertEqual(event.model, "gpt-5-codex")
        XCTAssertEqual(event.inputTokens, 85)  // 100 input_tokens − 15 cached
        XCTAssertEqual(event.outputTokens, 40)
        XCTAssertEqual(event.cacheReadTokens, 15)
        XCTAssertEqual(event.reasoningTokens, 7)
        XCTAssertEqual(event.totalTokens, 162)
    }

    func test_parseJSONLLines_extractsFromIncrementalLines() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("codex.jsonl")

        let adapter = CodexLocalUsageAdapter(root: root)
        let lines: [(Int?, String)] = [
            (1, #"{"type":"session_meta","payload":{"id":"codex-session","cwd":"/work","model_provider":"openai"}}"#),
            (2, #"{"type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5-codex","cwd":"/work"}}"#),
            (3, #"{"type":"event_msg","timestamp":"2026-06-09T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50,"output_tokens":20,"cached_input_tokens":0,"reasoning_output_tokens":0,"total_tokens":70}}}}"#),
        ]
        var context: LocalUsageParseContext?
        let events = try adapter.parseJSONLLines(lines, record: .appendOnlyJSONL(file), context: &context)

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertTrue(event.key.hasPrefix("codex:usage:"))
        XCTAssertEqual(event.sourceTool, "codex")
        XCTAssertEqual(event.totalTokens, 70)
        XCTAssertEqual(event.sourceCwd, "/work")
    }

    func test_parseJSONLLines_usesPersistedContextWhenBatchHasOnlyTokenCount() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("codex.jsonl")
        let adapter = CodexLocalUsageAdapter(root: root)
        var context: LocalUsageParseContext? = LocalUsageParseContext(
            sourceTool: "codex",
            json: #"{"sessionId":"codex-session","cwd":"/work","providerId":"openai","lastModel":"gpt-5-codex"}"#
        )
        let lines: [(Int?, String)] = [
            (42, #"{"type":"event_msg","timestamp":"2026-06-09T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50,"output_tokens":20,"cached_input_tokens":0,"reasoning_output_tokens":0,"total_tokens":70}}}}"#),
        ]

        let events = try adapter.parseJSONLLines(lines, record: .appendOnlyJSONL(file), context: &context)

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.model, "gpt-5-codex")
        XCTAssertEqual(event.providerId, "openai")
        XCTAssertEqual(event.sourceSessionId, "codex-session")
        XCTAssertEqual(event.sourceCwd, "/work")
    }

    func test_initialContext_scansPriorContextBeforeCheckpoint() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("codex.jsonl")
        let firstTwoLines = [
            #"{"type":"session_meta","payload":{"id":"codex-session","cwd":"/work","model_provider":"openai"}}"#,
            #"{"type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5-codex","cwd":"/work"}}"#,
        ]
        try writeJSONL(firstTwoLines + [
            #"{"type":"event_msg","timestamp":"2026-06-09T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}}}"#
        ], to: file)
        let offsetAfterContext = firstTwoLines.joined(separator: "\n").utf8.count + 1
        let checkpoint = LocalScanFileCheckpoint(
            sourceTool: "codex", path: file.path, fileSize: 0, modifiedAt: nil,
            fileId: nil, readOffset: offsetAfterContext, lastScannedAt: nil
        )

        let context = try XCTUnwrap(CodexLocalUsageAdapter(root: root).initialContext(record: .appendOnlyJSONL(file), checkpoint: checkpoint))

        XCTAssertTrue(context.json.contains("codex-session"))
        XCTAssertTrue(context.json.contains("gpt-5-codex"))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLensTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJSONL(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
