import XCTest
@testable import TokenLensApp

final class ClaudeCodeLocalUsageAdapterTests: XCTestCase {
    func test_readUsageChanges_extractsAssistantUsageAndSkipsMessagesWithoutUsage() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("claude.jsonl")
        try writeJSONL([
            #"{"type":"summary","summary":"redacted","sessionId":"s"}"#,
            #"{"type":"user","message":{"role":"user","content":"redacted"},"sessionId":"s"}"#,
            #"{"type":"assistant","id":"msg-1","timestamp":"2026-06-09T11:00:00Z","sessionId":"claude-session","cwd":"/Users/example/app","message":{"role":"assistant","model":"claude-sonnet-4-20250514","usage":{"input_tokens":200,"output_tokens":80,"cache_creation_input_tokens":30,"cache_read_input_tokens":20}},"costUSD":0.045}"#
        ], to: file)

        let adapter = ClaudeCodeLocalUsageAdapter(root: root)
        let events = try adapter.readUsageChanges(record: .appendOnlyJSONL(file), checkpoint: nil).events

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.key, "claude_code:native:msg-1")
        XCTAssertEqual(event.sourceTool, "claude_code")
        XCTAssertEqual(event.sourceSessionId, "claude-session")
        XCTAssertEqual(event.sourceCwd, "/Users/example/app")
        XCTAssertEqual(event.providerId, "anthropic")
        XCTAssertEqual(event.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(event.inputTokens, 200)
        XCTAssertEqual(event.outputTokens, 80)
        XCTAssertEqual(event.cacheWriteTokens, 30)
        XCTAssertEqual(event.cacheReadTokens, 20)
        XCTAssertEqual(event.totalTokens, 330)
        XCTAssertEqual(try XCTUnwrap(event.costUsd), 0.045, accuracy: 0.00001)
    }

    func test_parseJSONLLines_extractsFromIncrementalLines() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("claude.jsonl")

        let adapter = ClaudeCodeLocalUsageAdapter(root: root)
        let lines: [(Int?, String)] = [
            (1, #"{"type":"assistant","id":"msg-1","timestamp":"2026-06-09T11:00:00Z","cwd":"/app","message":{"role":"assistant","model":"claude-sonnet-4-20250514","usage":{"input_tokens":200,"output_tokens":80}},"costUSD":0.045}"#),
        ]
        var context: LocalUsageParseContext?
        let events = try adapter.parseJSONLLines(lines, record: .appendOnlyJSONL(file), context: &context)

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.key, "claude_code:native:msg-1")
        XCTAssertEqual(event.sourceTool, "claude_code")
        XCTAssertEqual(event.totalTokens, 280)
        XCTAssertEqual(event.sourceCwd, "/app")
        XCTAssertEqual(try XCTUnwrap(event.costUsd), 0.045, accuracy: 0.00001)
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
