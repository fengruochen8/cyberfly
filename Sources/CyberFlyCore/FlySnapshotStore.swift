import Foundation

public final class FlySnapshotStore: @unchecked Sendable {
    public static let widgetBundleIdentifier = "com.dadudu.CyberFly.Widget"

    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = FlySnapshotStore.defaultURL()) {
        self.fileURL = fileURL
        self.fileManager = .default
    }

    public var snapshotURL: URL { fileURL }

    public func load() -> FlyStateSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(FlyStateSnapshot.self, from: data)
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
}

