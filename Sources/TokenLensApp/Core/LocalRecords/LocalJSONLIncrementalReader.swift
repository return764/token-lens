import Foundation

// MARK: - Batch result

public struct IncrementalJSONLBatch {
    /// Parsed lines with optional line numbers.
    public let lines: [(lineNumber: Int?, text: String)]
    /// The byte offset where we started reading.
    public let startOffset: Int64
    /// The byte offset after the last complete newline we processed.
    public let nextOffset: Int64
    /// Total file size at the time of reading.
    public let fileSize: Int64
    /// File modification date at the time of reading.
    public let modifiedAt: Date?

    public init(lines: [(lineNumber: Int?, text: String)], startOffset: Int64, nextOffset: Int64, fileSize: Int64, modifiedAt: Date?) {
        self.lines = lines
        self.startOffset = startOffset
        self.nextOffset = nextOffset
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Reader

public struct LocalJSONLIncrementalReader {

    public init() {}

    /// Read new complete JSONL lines from `url`, starting at byte `offset`.
    ///
    /// - Parameter url: The JSONL file to read.
    /// - Parameter offset: Byte offset to start reading from (0 for full read).
    /// - Returns: An `IncrementalJSONLBatch` with the new lines and the next safe offset.
    ///
    /// Rules:
    /// - If the file size < offset, treat as truncate/rotate and read from 0.
    /// - Only return lines that end with `\n` — trailing incomplete line is retained for next read.
    /// - `nextOffset` is the byte position immediately after the last `\n` we processed.
    public func readNewLines(url: URL, from offset: Int64) throws -> IncrementalJSONLBatch {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = attrs[.modificationDate] as? Date

        // Truncate/rotate detection: file is smaller than our checkpoint
        let effectiveOffset: Int64
        if fileSize < offset {
            effectiveOffset = 0
        } else {
            effectiveOffset = offset
        }

        guard fileSize > effectiveOffset else {
            return IncrementalJSONLBatch(
                lines: [],
                startOffset: effectiveOffset,
                nextOffset: effectiveOffset,
                fileSize: fileSize,
                modifiedAt: modifiedAt
            )
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(effectiveOffset))
        let remaining = fileSize - effectiveOffset
        guard let data = try handle.read(upToCount: Int(remaining)), !data.isEmpty else {
            return IncrementalJSONLBatch(
                lines: [],
                startOffset: effectiveOffset,
                nextOffset: effectiveOffset,
                fileSize: fileSize,
                modifiedAt: modifiedAt
            )
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw LocalJSONLIncrementalReaderError.encodingError
        }

        return parseLines(text: text, startOffset: effectiveOffset, fileSize: fileSize, modifiedAt: modifiedAt)
    }

    // MARK: - Internal parsing

    func parseLines(text: String, startOffset: Int64, fileSize: Int64, modifiedAt: Date?) -> IncrementalJSONLBatch {
        var lines: [(Int?, String)] = []
        var currentOffset = startOffset
        var lineStartOffset = startOffset
        var lastNewlineOffset = startOffset
        var lineNumber = 1

        let scalars = Array(text.unicodeScalars)
        var currentLine = ""

        for scalar in scalars {
            currentOffset += Int64(scalar.utf8.count > 0 ? scalar.utf8.count : 1)

            if scalar == "\n" {
                // Complete line found — include it
                let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    lines.append((lineNumber, currentLine))
                }
                lineNumber += 1
                currentLine = ""
                lastNewlineOffset = currentOffset
            } else {
                currentLine.append(String(scalar))
            }
        }

        // Trailing content without newline = incomplete line, don't advance past it
        let nextOffset = lastNewlineOffset

        return IncrementalJSONLBatch(
            lines: lines,
            startOffset: startOffset,
            nextOffset: nextOffset,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }
}

// MARK: - Errors

public enum LocalJSONLIncrementalReaderError: Error, LocalizedError {
    case encodingError

    public var errorDescription: String? {
        switch self {
        case .encodingError:
            return "File is not valid UTF-8"
        }
    }
}
