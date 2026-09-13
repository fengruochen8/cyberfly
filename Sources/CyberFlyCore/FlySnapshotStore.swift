import Foundation

public enum PersistentLoadResult<Value: Sendable>: Sendable {
    case missing
    case loaded(Value)
    case quarantined(fileURL: URL, reason: String)
}

public enum PersistentFileLoadError: Error, LocalizedError, Sendable {
    case readFailed(path: String, reason: String)
    case quarantineFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .readFailed(path, reason):
            "无法读取持久化文件 \(path)：\(reason)"
        case let .quarantineFailed(path, reason):
            "持久化文件损坏且无法隔离 \(path)：\(reason)"
        }
    }
}

public final class FlySnapshotStore: @unchecked Sendable {
    public static let widgetBundleIdentifier = "com.dadudu.CyberFly.Widget"

    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = FlySnapshotStore.defaultURL()) {
        self.fileURL = fileURL
        self.fileManager = .default
    }

    public var snapshotURL: URL { fileURL }

    /// Decodes the shared snapshot without renaming or deleting it on failure.
    /// Readers such as WidgetKit must never mutate the app's single-writer file.
    public func loadReadOnly() throws -> FlyStateSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw PersistentFileLoadError.readFailed(
                path: fileURL.path,
                reason: error.localizedDescription
            )
        }
        return try decoder.decode(FlyStateSnapshot.self, from: data)
    }

    public func load() throws -> PersistentLoadResult<FlyStateSnapshot> {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw PersistentFileLoadError.readFailed(
                path: fileURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            return .loaded(try decoder.decode(FlyStateSnapshot.self, from: data))
        } catch {
            let reason = error.localizedDescription
            return .quarantined(
                fileURL: try quarantineUnreadableFile(reason: reason),
                reason: reason
            )
        }
    }

    public func save(_ snapshot: FlyStateSnapshot) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func defaultURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CYBERFLY_SNAPSHOT_PATH"] {
            return URL(fileURLWithPath: override)
        }
        return isWidgetProcess ? widgetReaderURL() : appWriterURL()
    }

    private static var isWidgetProcess: Bool {
        Bundle.main.bundleIdentifier == widgetBundleIdentifier
    }

    private static func widgetReaderURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CyberFly/fly-state.json")
    }

    private static func appWriterURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(widgetBundleIdentifier)/Data/Library/Application Support")
            .appendingPathComponent("CyberFly/fly-state.json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func quarantineUnreadableFile(reason: String) throws -> URL {
        let quarantineURL = fileURL.appendingPathExtension(
            "corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
        )
        do {
            try fileManager.moveItem(at: fileURL, to: quarantineURL)
            return quarantineURL
        } catch {
            throw PersistentFileLoadError.quarantineFailed(
                path: fileURL.path,
                reason: "\(reason); \(error.localizedDescription)"
            )
        }
    }
}
