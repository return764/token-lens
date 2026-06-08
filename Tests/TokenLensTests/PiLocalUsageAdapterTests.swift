import XCTest
@testable import TokenLensApp

final class PiLocalUsageAdapterTests: XCTestCase {
    func test_parseFile_extractsAssistantUsageFromPiSession() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("session.jsonl")
        try writeJSONL([
            #"{"type":"session","id":"sess-1","cwd":"/Users/example/project"}"#,
            #"{"type":"message","id":"user-1","message":{"role":"user","content":"redacted"}}"#,
            #"{"type":"message","id":"assistant-error","timestamp":"2026-06-09T10:11:10Z","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-4-20250514","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0,"cost":{"total":0}},"stopReason":"error","errorMessage":"terminated"}}"#,
            #"{"type":"message","id":"assistant-1","timestamp":"2026-06-09T10:11:12Z","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-4-20250514","usage":{"input":120,"output":34,"cacheRead":10,"cacheWrite":5,"totalTokens":169,"cost":{"total":0.0123}}}}"#,
            #"{"type":"message","id":"assistant-no-usage","message":{"role":"assistant"}}"#
        ], to: file)

        let adapter = PiLocalUsageAdapter(root: root)
        let events = try adapter.parseFile(file)

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.key, "pi:native:assistant-1")
        XCTAssertEqual(event.sourceTool, "pi")
        XCTAssertEqual(event.sourceEventId, "assistant-1")
        XCTAssertEqual(event.sourceSessionId, "sess-1")
        XCTAssertEqual(event.sourceCwd, "/Users/example/project")
        XCTAssertEqual(event.providerId, "anthropic")
        XCTAssertEqual(event.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(event.inputTokens, 120)
        XCTAssertEqual(event.outputTokens, 34)
        XCTAssertEqual(event.cacheReadTokens, 10)
        XCTAssertEqual(event.cacheWriteTokens, 5)
        XCTAssertEqual(event.totalTokens, 169)
        XCTAssertEqual(try XCTUnwrap(event.costUsd), 0.0123, accuracy: 0.00001)
    }

    func test_parseLines_extractsFromIncrementalLines() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("session.jsonl")

        let adapter = PiLocalUsageAdapter(root: root)
        let lines: [(Int?, String)] = [
            (1, #"{"type":"session","id":"sess-1","cwd":"/Users/example/project"}"#),
            (2, #"{"type":"message","id":"assistant-error","timestamp":"2026-06-09T10:11:10Z","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-4-20250514","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0},"stopReason":"error","errorMessage":"terminated"}}"#),
            (3, #"{"type":"message","id":"assistant-1","timestamp":"2026-06-09T10:11:12Z","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-4-20250514","usage":{"input":120,"output":34,"totalTokens":154}}}"#),
        ]
        var context: LocalUsageParseContext?
        let events = try adapter.parseLines(lines, file: file, context: &context)

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.key, "pi:native:assistant-1")
        XCTAssertEqual(event.sourceTool, "pi")
        XCTAssertEqual(event.totalTokens, 154)
        XCTAssertEqual(event.sourceCwd, "/Users/example/project")
    }

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
