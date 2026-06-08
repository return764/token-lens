import Foundation

/// macOS FSEvents-based recursive directory watcher.
/// Notifies callers of changed paths under a root directory.
public final class FileSystemEventWatcher {
    private let root: URL
    private let onEvents: ([URL]) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.tokenlens.fsevents")

    /// - Parameters:
    ///   - root: Directory to watch recursively.
    ///   - onEvents: Callback invoked with a deduplicated list of affected file paths.
    public init(root: URL, onEvents: @escaping ([URL]) -> Void) {
        self.root = root
        self.onEvents = onEvents
    }

    /// Start watching. Throws if the root doesn't exist or isn't a directory.
    public func start() throws {
        guard FileManager.default.fileExists(atPath: root.path) else {
            print("[TokenLens] ⚠️ Watcher root not found: \(root.path)")
            throw FileSystemEventWatcherError.rootNotFound(root.path)
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            print("[TokenLens] ⚠️ Watcher path is not a directory: \(root.path)")
            throw FileSystemEventWatcherError.notDirectory(root.path)
        }

        print("[TokenLens] 👁️  Starting watcher on: \(root.path)")
        stop()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [root.path] as CFArray
        let latency: CFTimeInterval = 1.0  // 1 second coalescing

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, numEvents, eventPaths, eventFlags, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileSystemEventWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleEvents(
                    numEvents: numEvents,
                    eventPaths: eventPaths,
                    eventFlags: eventFlags
                )
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            throw FileSystemEventWatcherError.streamCreationFailed
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            throw FileSystemEventWatcherError.startFailed
        }

        self.stream = stream
    }

    /// Stop watching.
    public func stop() {
        guard let stream = stream else { return }
        print("[TokenLens] 🛑 Stopping watcher on: \(root.path)")
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - Event handling

    private func handleEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

        let urls = candidateJSONLFiles(for: paths)

        if !urls.isEmpty {
            let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
            print("[TokenLens] 📁 FSEvent: \(urls.count) JSONL candidate(s) changed → \(names)")
            onEvents(urls)
        }
    }

    /// Convert raw FSEvent paths into existing JSONL files to import.
    /// FSEvents can report a parent directory (especially when Codex creates date
    /// subdirectories or coalesces bursts), so directory paths are expanded recursively.
    func candidateJSONLFiles(for paths: [String]) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []

        func append(_ url: URL) {
            let canonical = url.resolvingSymlinksInPath()
            guard seen.insert(canonical.path).inserted else { return }
            urls.append(canonical)
        }

        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                for file in (try? LocalRecordJSON.discoverJSONLFiles(root: url)) ?? [] {
                    append(file)
                }
            } else if url.pathExtension == "jsonl" {
                append(url)
            }
        }

        return urls.sorted { $0.path < $1.path }
    }

    deinit {
        stop()
    }
}

// MARK: - Errors

public enum FileSystemEventWatcherError: Error, LocalizedError {
    case rootNotFound(String)
    case notDirectory(String)
    case streamCreationFailed
    case startFailed

    public var errorDescription: String? {
        switch self {
        case .rootNotFound(let path):
            return "Watch root not found: \(path)"
        case .notDirectory(let path):
            return "Watch path is not a directory: \(path)"
        case .streamCreationFailed:
            return "Failed to create FSEventStream"
        case .startFailed:
            return "Failed to start FSEventStream"
        }
    }
}
