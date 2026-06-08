import XCTest
@testable import TokenLensApp

final class LocalJSONLIncrementalReaderTests: XCTestCase {

    // MARK: - Basic offset reading

    func test_readNewLines_fromStart_returnsAllCompleteLines() throws {
        let (file, _) = try writeTempFile(content: "line1\nline2\nline3\n")
        let reader = LocalJSONLIncrementalReader()

        let batch = try reader.readNewLines(url: file, from: 0)

        XCTAssertEqual(batch.lines.count, 3)
        XCTAssertEqual(batch.lines[0].text, "line1")
        XCTAssertEqual(batch.lines[1].text, "line2")
        XCTAssertEqual(batch.lines[2].text, "line3")
        XCTAssertEqual(batch.startOffset, 0)
        XCTAssertEqual(batch.nextOffset, 18) // 3 lines × "lineN\n" = 6+6+6 = 18
        XCTAssertEqual(batch.fileSize, 18)
    }

    func test_readNewLines_fromOffset_skipsAlreadyProcessedLines() throws {
        let content = "line1\nline2\nline3\n"
        let (file, _) = try writeTempFile(content: content)
        let reader = LocalJSONLIncrementalReader()

        // First read from offset 6 (after "line1\n")
        let batch = try reader.readNewLines(url: file, from: 6)

        XCTAssertEqual(batch.lines.count, 2)
        XCTAssertEqual(batch.lines[0].text, "line2")
        XCTAssertEqual(batch.lines[1].text, "line3")
        XCTAssertEqual(batch.startOffset, 6)
        XCTAssertEqual(batch.nextOffset, 18)
    }

    // MARK: - Half-line handling

    func test_readNewLines_halfLine_notAdvanced() throws {
        let content = "line1\nline2"
        let (file, _) = try writeTempFile(content: content)
        let reader = LocalJSONLIncrementalReader()

        let batch = try reader.readNewLines(url: file, from: 0)

        XCTAssertEqual(batch.lines.count, 1)
        XCTAssertEqual(batch.lines[0].text, "line1")
        // nextOffset should be after "line1\n" (6), not including "line2"
        XCTAssertEqual(batch.nextOffset, 6)
        XCTAssertEqual(batch.fileSize, 11)
    }

    func test_readNewLines_halfLine_becomesCompleteOnNextRead() throws {
        let (file, dir) = try writeTempFile(content: "line1\nline2")
        let reader = LocalJSONLIncrementalReader()

        // First read: half line
        let batch1 = try reader.readNewLines(url: file, from: 0)
        XCTAssertEqual(batch1.lines.count, 1)
        XCTAssertEqual(batch1.nextOffset, 6)

        // Append to file
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: "3\n".data(using: .utf8)!)
        try handle.close()

        // Second read: should get the completed line
        let batch2 = try reader.readNewLines(url: file, from: batch1.nextOffset)
        XCTAssertEqual(batch2.lines.count, 1)
        XCTAssertEqual(batch2.lines[0].text, "line23")
        XCTAssertEqual(batch2.startOffset, 6)
        XCTAssertEqual(batch2.nextOffset, 13)
    }

    // MARK: - Truncate / rotate detection

    func test_readNewLines_truncatedFile_resetsToZero() throws {
        let (file, _) = try writeTempFile(content: "line1\nline2\nline3\n")
        let reader = LocalJSONLIncrementalReader()

        // First read with a fake large offset that exceeds file size
        let batch = try reader.readNewLines(url: file, from: 999)

        // Should reset to 0 and read all
        XCTAssertEqual(batch.startOffset, 0)
        XCTAssertEqual(batch.lines.count, 3)
        XCTAssertEqual(batch.lines[0].text, "line1")
    }

    // MARK: - Empty file

    func test_readNewLines_emptyFile_returnsEmptyBatch() throws {
        let (file, _) = try writeTempFile(content: "")
        let reader = LocalJSONLIncrementalReader()

        let batch = try reader.readNewLines(url: file, from: 0)
        XCTAssertEqual(batch.lines.count, 0)
        XCTAssertEqual(batch.nextOffset, 0)
        XCTAssertEqual(batch.fileSize, 0)
    }

    func test_readNewLines_fileWithOnlyNewline_returnsEmptyLines() throws {
        let (file, _) = try writeTempFile(content: "\n\n\n")
        let reader = LocalJSONLIncrementalReader()

        let batch = try reader.readNewLines(url: file, from: 0)
        // Whitespace-only lines should be skipped
        XCTAssertEqual(batch.lines.count, 0)
        XCTAssertEqual(batch.nextOffset, 3)
    }

    // MARK: - No new content

    func test_readNewLines_noNewContent_returnsEmptyBatch() throws {
        let content = "line1\n"
        let (file, _) = try writeTempFile(content: content)
        let reader = LocalJSONLIncrementalReader()

        // Read it all
        let batch1 = try reader.readNewLines(url: file, from: 0)
        XCTAssertEqual(batch1.lines.count, 1)

        // Read again from the same offset — no new content
        let batch2 = try reader.readNewLines(url: file, from: batch1.nextOffset)
        XCTAssertEqual(batch2.lines.count, 0)
        XCTAssertEqual(batch2.nextOffset, batch1.nextOffset)
    }

    // MARK: - JSONL content

    func test_readNewLines_jsonlLines() throws {
        let content = """
        {"type":"session","id":"s1"}
        {"type":"message","id":"m1"}

        """
        let (file, _) = try writeTempFile(content: content)
        let reader = LocalJSONLIncrementalReader()

        let batch = try reader.readNewLines(url: file, from: 0)
        XCTAssertEqual(batch.lines.count, 2)
        XCTAssertEqual(batch.lines[0].text, #"{"type":"session","id":"s1"}"#)
        XCTAssertEqual(batch.lines[1].text, #"{"type":"message","id":"m1"}"#)
    }

    // MARK: - Helpers

    private func writeTempFile(content: String) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLensTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)
        return (file, dir)
    }
}
