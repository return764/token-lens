import Foundation

public struct LocalUsageEvent: Equatable {
    public let key: String
    public let sourceTool: String
    public let sourceFile: String
    public let sourceEventId: String
    public let sourceSessionId: String?
    public let sourceCwd: String?
    public let timestamp: Date
    public let providerId: String?
    public let model: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let costUsd: Double?

    public init(
        key: String,
        sourceTool: String,
        sourceFile: String,
        sourceEventId: String,
        sourceSessionId: String?,
        sourceCwd: String?,
        timestamp: Date,
        providerId: String?,
        model: String?,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int,
        costUsd: Double?
    ) {
        self.key = key
        self.sourceTool = sourceTool
        self.sourceFile = sourceFile
        self.sourceEventId = sourceEventId
        self.sourceSessionId = sourceSessionId
        self.sourceCwd = sourceCwd
        self.timestamp = timestamp
        self.providerId = providerId
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.costUsd = costUsd
    }
}

public struct LocalUsageParseContext: Equatable {
    public let sourceTool: String
    public var json: String

    public init(sourceTool: String, json: String) {
        self.sourceTool = sourceTool
        self.json = json
    }
}

public struct LocalUsageRecord: Equatable, Hashable {
    public let readURL: URL
    public let checkpointURL: URL
    public let displayPath: String
    public let kind: LocalUsageRecordKind

    public init(readURL: URL, checkpointURL: URL, displayPath: String? = nil, kind: LocalUsageRecordKind) {
        self.readURL = readURL
        self.checkpointURL = checkpointURL
        self.displayPath = displayPath ?? readURL.path
        self.kind = kind
    }

    public static func appendOnlyJSONL(_ url: URL) -> LocalUsageRecord {
        let canonical = url.resolvingSymlinksInPath()
        return LocalUsageRecord(readURL: canonical, checkpointURL: canonical, kind: .appendOnlyJSONL)
    }
}

public enum LocalUsageRecordKind: Equatable, Hashable {
    case appendOnlyJSONL
    case sqliteDatabase
}

public protocol LocalUsageAdapter {
    var id: String { get }
    var displayName: String { get }
    var defaultRoot: URL { get }

    func discoverRecords() throws -> [LocalUsageRecord]
    func candidates(fromChangedPaths paths: [URL]) throws -> [LocalUsageRecord]
    func readUsageChanges(record: LocalUsageRecord, checkpoint: LocalScanFileCheckpoint?) throws -> LocalUsageSessionReadResult
}

public struct LocalUsageSessionReadResult: Equatable {
    public let events: [LocalUsageEvent]
    public let checkpoint: LocalScanFileCheckpointUpdate
    public let observedSize: Int
    public let shouldReenqueue: Bool

    public init(
        events: [LocalUsageEvent],
        checkpoint: LocalScanFileCheckpointUpdate,
        observedSize: Int,
        shouldReenqueue: Bool
    ) {
        self.events = events
        self.checkpoint = checkpoint
        self.observedSize = observedSize
        self.shouldReenqueue = shouldReenqueue
    }
}

// MARK: - Checkpoint types

public struct LocalScanFileCheckpoint: Equatable {
    public let sourceTool: String
    public let path: String
    public let fileSize: Int
    public let modifiedAt: Date?
    public let fileId: String?
    public let readOffset: Int
    public let lastScannedAt: Date?
    public let parseContext: LocalUsageParseContext?

    public init(sourceTool: String, path: String, fileSize: Int, modifiedAt: Date?, fileId: String?, readOffset: Int, lastScannedAt: Date?, parseContext: LocalUsageParseContext? = nil) {
        self.sourceTool = sourceTool
        self.path = path
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.fileId = fileId
        self.readOffset = readOffset
        self.lastScannedAt = lastScannedAt
        self.parseContext = parseContext
    }
}

public struct LocalScanFileCheckpointUpdate: Equatable {
    public let sourceTool: String
    public let path: String
    public let fileSize: Int
    public let modifiedAt: Date?
    public let fileId: String?
    public let readOffset: Int
    public let parseContext: LocalUsageParseContext?
    public let importedEventCount: Int
    public let status: String
    public let lastError: String?

    public init(sourceTool: String, path: String, fileSize: Int, modifiedAt: Date?, fileId: String?, readOffset: Int, parseContext: LocalUsageParseContext? = nil, importedEventCount: Int, status: String, lastError: String?) {
        self.sourceTool = sourceTool
        self.path = path
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.fileId = fileId
        self.readOffset = readOffset
        self.parseContext = parseContext
        self.importedEventCount = importedEventCount
        self.status = status
        self.lastError = lastError
    }
}

public enum LocalUsageParseError: Error, LocalizedError {
    case invalidJSON(line: Int)
    case unsupportedSourceSchema(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let line):
            return "Invalid JSONL at line \(line)"
        case .unsupportedSourceSchema(let message):
            return message
        }
    }
}

enum LocalRecordJSON {

    static func object(from line: String, lineNumber: Int) throws -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalUsageParseError.invalidJSON(line: lineNumber)
        }
        return object
    }

    static func string(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }

    static func int(_ dict: [String: Any], _ key: String) -> Int {
        if let value = dict[key] as? Int { return value }
        if let value = dict[key] as? Double { return Int(value) }
        if let value = dict[key] as? String, let int = Int(value) { return int }
        return 0
    }

    static func double(_ dict: [String: Any], _ key: String) -> Double? {
        if let value = dict[key] as? Double { return value }
        if let value = dict[key] as? Int { return Double(value) }
        if let value = dict[key] as? String { return Double(value) }
        return nil
    }

    static func date(_ dict: [String: Any], keys: [String]) -> Date {
        for key in keys {
            if let value = dict[key] as? String, let date = ISO8601DateCoding.parse(value) {
                return date
            }
        }
        return Date()
    }

    static func discoverJSONLFiles(root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    static func discoverJSONLRecords(root: URL) throws -> [LocalUsageRecord] {
        try discoverJSONLFiles(root: root).map(LocalUsageRecord.appendOnlyJSONL)
    }

    static func candidateJSONLFiles(for paths: [URL]) throws -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []

        func append(_ url: URL) {
            let canonical = url.resolvingSymlinksInPath()
            guard seen.insert(canonical.path).inserted else { return }
            urls.append(canonical)
        }

        for url in paths {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                for file in try discoverJSONLFiles(root: url) {
                    append(file)
                }
            } else if url.pathExtension == "jsonl" {
                append(url)
            }
        }

        return urls.sorted { $0.path < $1.path }
    }

    static func candidateJSONLRecords(for paths: [URL]) throws -> [LocalUsageRecord] {
        try candidateJSONLFiles(for: paths).map(LocalUsageRecord.appendOnlyJSONL)
    }
}
