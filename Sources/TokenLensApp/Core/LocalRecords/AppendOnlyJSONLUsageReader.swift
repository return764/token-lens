import Foundation

public protocol AppendOnlyJSONLUsageDecoding {
    var id: String { get }

    func initialContext(
        record: LocalUsageRecord,
        checkpoint: LocalScanFileCheckpoint?
    ) throws -> LocalUsageParseContext?

    func parseJSONLLines(
        _ lines: [(lineNumber: Int?, text: String)],
        record: LocalUsageRecord,
        context: inout LocalUsageParseContext?
    ) throws -> [LocalUsageEvent]
}

public extension AppendOnlyJSONLUsageDecoding {
    func initialContext(
        record: LocalUsageRecord,
        checkpoint: LocalScanFileCheckpoint?
    ) throws -> LocalUsageParseContext? {
        checkpoint?.parseContext
    }
}

public struct AppendOnlyJSONLUsageReader {
    private let reader: LocalJSONLIncrementalReader

    public init(reader: LocalJSONLIncrementalReader = LocalJSONLIncrementalReader()) {
        self.reader = reader
    }

    public func readChanges(
        record: LocalUsageRecord,
        checkpoint: LocalScanFileCheckpoint?,
        decoder: any AppendOnlyJSONLUsageDecoding
    ) throws -> LocalUsageSessionReadResult {
        let readOffset = Int64(checkpoint?.readOffset ?? 0)
        let batch = try reader.readNewLines(url: record.readURL, from: readOffset)
        var parseContext = try decoder.initialContext(record: record, checkpoint: checkpoint)
        let events = try decoder.parseJSONLLines(batch.lines, record: record, context: &parseContext)
        let checkpointUpdate = LocalScanFileCheckpointUpdate(
            sourceTool: decoder.id,
            path: record.checkpointURL.path,
            fileSize: Int(batch.fileSize),
            modifiedAt: batch.modifiedAt,
            fileId: checkpoint?.fileId,
            readOffset: Int(batch.nextOffset),
            parseContext: parseContext,
            importedEventCount: events.count,
            status: "ok",
            lastError: nil
        )

        return LocalUsageSessionReadResult(
            events: events,
            checkpoint: checkpointUpdate,
            observedSize: Int(batch.fileSize),
            shouldReenqueue: batch.fileSize > batch.nextOffset
        )
    }
}
