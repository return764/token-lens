import XCTest
@testable import TokenLensApp

final class FileSystemEventWatcherTests: XCTestCase {
    func test_candidateJSONLFiles_expandsDirectoryEvents() throws {
        let root = try makeTempDirectory()
        let nested = root.appendingPathComponent("2026/06/12", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let jsonl = nested.appendingPathComponent("rollout.jsonl")
        let ignored = nested.appendingPathComponent("notes.txt")
        try "{}\n".write(to: jsonl, atomically: true, encoding: .utf8)
        try "ignore".write(to: ignored, atomically: true, encoding: .utf8)

        let watcher = FileSystemEventWatcher(root: root, onEvents: { _ in })
        let candidates = watcher.candidateJSONLFiles(for: [nested.path])

        XCTAssertEqual(candidates, [jsonl.resolvingSymlinksInPath()])
    }

    func test_candidateJSONLFiles_deduplicatesFileAndDirectoryEvents() throws {
        let root = try makeTempDirectory()
        let jsonl = root.appendingPathComponent("session.jsonl")
        try "{}\n".write(to: jsonl, atomically: true, encoding: .utf8)

        let watcher = FileSystemEventWatcher(root: root, onEvents: { _ in })
        let candidates = watcher.candidateJSONLFiles(for: [root.path, jsonl.path])

        XCTAssertEqual(candidates, [jsonl.resolvingSymlinksInPath()])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLensTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
