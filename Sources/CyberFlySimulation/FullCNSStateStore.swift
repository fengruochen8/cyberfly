import CyberFlyCore
import Foundation

public final class FullCNSStateStore: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL) {
        self.fileURL = fileURL
        fileManager = .default
    }

    public func load(
        matching individualID: UUID,
        graphSHA256: String,
        nodeCount: Int
    ) throws -> PersistentLoadResult<FullCNSPersistentState> {
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
            let state = try PropertyListDecoder().decode(FullCNSPersistentState.self, from: data)
            guard state.schemaVersion == FullCNSPersistentState.currentSchemaVersion else {
                throw FullCNSStateError.unsupportedSchema(state.schemaVersion)
            }
            guard state.individualID == individualID else {
                throw FullCNSStateError.individualMismatch
            }
            try state.validate(graphSHA256: graphSHA256, nodeCount: nodeCount)
            return .loaded(state)
        } catch {
            return try quarantine(reason: error.localizedDescription)
        }
    }

    public func save(_ state: FullCNSPersistentState) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func nextToSnapshot(_ snapshotURL: URL) -> FullCNSStateStore {
        FullCNSStateStore(
            fileURL: snapshotURL.deletingLastPathComponent()
                .appendingPathComponent("full-cns-state.plist")
        )
    }

    private func quarantine(
        reason: String
    ) throws -> PersistentLoadResult<FullCNSPersistentState> {
        let quarantineURL = fileURL.appendingPathExtension(
            "corrupt-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
        )
        do {
            try fileManager.moveItem(at: fileURL, to: quarantineURL)
            return .quarantined(fileURL: quarantineURL, reason: reason)
        } catch {
            throw PersistentFileLoadError.quarantineFailed(
                path: fileURL.path,
                reason: "\(reason); \(error.localizedDescription)"
            )
        }
    }
}
