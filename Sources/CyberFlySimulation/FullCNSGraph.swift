import CryptoKit
import Foundation

public struct FullCNSNodeRole: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let sensory = FullCNSNodeRole(rawValue: 1 << 0)
    public static let motor = FullCNSNodeRole(rawValue: 1 << 1)
    public static let descending = FullCNSNodeRole(rawValue: 1 << 2)
    public static let ascending = FullCNSNodeRole(rawValue: 1 << 3)
    public static let visual = FullCNSNodeRole(rawValue: 1 << 4)
    public static let olfactory = FullCNSNodeRole(rawValue: 1 << 5)
    public static let gustatory = FullCNSNodeRole(rawValue: 1 << 6)
    public static let mechanosensory = FullCNSNodeRole(rawValue: 1 << 7)
    public static let centralComplex = FullCNSNodeRole(rawValue: 1 << 8)
    public static let mushroomBody = FullCNSNodeRole(rawValue: 1 << 9)
    public static let dopaminergic = FullCNSNodeRole(rawValue: 1 << 10)
    public static let neurosecretory = FullCNSNodeRole(rawValue: 1 << 11)
    public static let sexSpecific = FullCNSNodeRole(rawValue: 1 << 12)
}

public enum FullCNSHemisphere: UInt8, Codable, Sendable {
    case unknown = 0
    case left = 1
    case right = 2
    case midline = 3
}

public enum FullCNSNeurotransmitter: UInt8, Codable, CaseIterable, Sendable {
    case unclear = 0
    case acetylcholine = 1
    case gaba = 2
    case glutamate = 3
    case dopamine = 4
    case serotonin = 5
    case octopamine = 6
    case histamine = 7

    /// Sign is a runtime assumption, not an observation in MaleCNS.
    public var assumedFastSign: Float {
        switch self {
        case .gaba, .glutamate, .histamine: -1
        case .acetylcholine: 1
        case .unclear, .dopamine, .serotonin, .octopamine: 0
        }
    }

    public var isModulator: Bool {
        switch self {
        case .dopamine, .serotonin, .octopamine: true
        default: false
        }
    }
}

public struct FullCNSNode: Equatable, Sendable {
    public let bodyID: UInt64
    public let roles: FullCNSNodeRole
    public let transmitter: FullCNSNeurotransmitter
    public let hemisphere: FullCNSHemisphere
    public let traceQuality: UInt8
    public let somaX: Int32?
    public let somaY: Int32?
    public let somaZ: Int32?
    public let transmitterConfidence: Float
}

public struct FullCNSManifest: Codable, Equatable, Sendable {
    public struct Provenance: Codable, Equatable, Sendable {
        public let nodes: String
        public let edges: String
        public let weights: String
        public let neurotransmitters: String
        public let roles: String
        public let dynamics: String
    }

    public struct FileRecord: Codable, Equatable, Sendable {
        public let name: String
        public let bytes: Int
        public let sha256: String
    }

    public let schemaVersion: Int
    public let format: String
    public let dataset: String
    public let license: String
    public let compiledAt: String
    public let nodeRecordBytes: Int
    public let nodeCount: Int
    public let edgeCount: Int
    public let sourceWeightRowCount: Int
    public let synapseWeightSum: UInt64
    public let maximumEdgeWeight: UInt32
    public let graphSha256: String
    public let nodeOrdering: String
    public let edgeAggregation: String
    public let outgoingOrdering: String
    public let incomingOrdering: String
    public let provenance: Provenance
    public let sourceSha256: [String: String]
    public let roleBits: [String: UInt32]
    public let roleCounts: [String: Int]
    public let transmitterCodes: [String: UInt8]
    public let transmitterCounts: [String: Int]
    public let files: [FileRecord]
    public let compileSeconds: Double
}

public enum FullCNSGraphError: Error, LocalizedError {
    case missingResource(String)
    case invalidManifest(String)
    case invalidBinary(String)
    case unsupportedHost

    public var errorDescription: String? {
        switch self {
        case let .missingResource(name): "缺少全 CNS 资源：\(name)"
        case let .invalidManifest(reason): "全 CNS manifest 无效：\(reason)"
        case let .invalidBinary(reason): "全 CNS 二进制无效：\(reason)"
        case .unsupportedHost: "全 CNS 二进制目前只支持小端平台"
        }
    }
}

public struct FullCNSValidationReport: Equatable, Sendable {
    public let nodeCount: Int
    public let edgeCount: Int
    public let synapseWeightSum: UInt64
    public let incomingSynapseWeightSum: UInt64
    public let zeroOutDegreeNodeCount: Int
    public let zeroInDegreeNodeCount: Int
    public let maximumOutDegree: Int
    public let maximumInDegree: Int
    public let bodyIDsStrictlyAscending: Bool
    public let targetsInBounds: Bool
    public let sourcesInBounds: Bool
    public let fileChecksumsMatch: Bool
    public let graphChecksumMatchesPinnedArtifact: Bool

    public var isExact: Bool {
        nodeCount > 0
            && edgeCount > 0
            && synapseWeightSum == incomingSynapseWeightSum
            && bodyIDsStrictlyAscending
            && targetsInBounds
            && sourcesInBounds
            && fileChecksumsMatch
            && graphChecksumMatchesPinnedArtifact
    }
}

/// Memory-mapped, lossless representation of every traced MaleCNS v1.0 body
/// and every aggregated connection whose endpoints are both traced.
public final class FullCNSGraph: @unchecked Sendable {
    public static let expectedFormat = "cyberfly-full-cns-v1"
    public static let pinnedGraphSHA256 = "35c7973b35f4b0508d2542ebca1e7db48becab3c1b6a3c76e8cc1b78663478a3"
    public static let nodeRecordBytes = 32
    private static let missingCoordinate = Int32.min

    public let manifest: FullCNSManifest
    public let directoryURL: URL

    private let nodes: Data
    private let outgoingOffsets: Data
    private let outgoingTargets: Data
    private let outgoingWeights: Data
    private let incomingOffsets: Data
    private let incomingSources: Data
    private let incomingWeights: Data
    private let indicesByRoleBit: [UInt32: [UInt32]]
    private let leftDescendingIndices: [UInt32]
    private let rightDescendingIndices: [UInt32]

    public init(directoryURL: URL) throws {
        guard CFByteOrderGetCurrent() == CFByteOrderLittleEndian.rawValue else {
            throw FullCNSGraphError.unsupportedHost
        }
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw FullCNSGraphError.missingResource("manifest.json")
        }
        let loadedManifest: FullCNSManifest
        do {
            loadedManifest = try JSONDecoder().decode(
                FullCNSManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw FullCNSGraphError.invalidManifest(error.localizedDescription)
        }
        guard loadedManifest.schemaVersion == 1,
              loadedManifest.format == Self.expectedFormat,
              loadedManifest.graphSha256 == Self.pinnedGraphSHA256,
              loadedManifest.nodeRecordBytes == Self.nodeRecordBytes,
              loadedManifest.nodeCount > 0,
              loadedManifest.edgeCount > 0 else {
            throw FullCNSGraphError.invalidManifest("格式、版本或计数不受支持")
        }

        let nodeData = try Self.map("nodes.bin", in: directoryURL)
        let outOffsetsData = try Self.map("out-offsets.bin", in: directoryURL)
        let outTargetsData = try Self.map("out-targets.bin", in: directoryURL)
        let outWeightsData = try Self.map("out-weights.bin", in: directoryURL)
        let inOffsetsData = try Self.map("in-offsets.bin", in: directoryURL)
        let inSourcesData = try Self.map("in-sources.bin", in: directoryURL)
        let inWeightsData = try Self.map("in-weights.bin", in: directoryURL)

        try Self.requireSize(nodeData, loadedManifest.nodeCount * Self.nodeRecordBytes, "nodes.bin")
        try Self.requireSize(outOffsetsData, (loadedManifest.nodeCount + 1) * 8, "out-offsets.bin")
        try Self.requireSize(outTargetsData, loadedManifest.edgeCount * 4, "out-targets.bin")
        try Self.requireSize(outWeightsData, loadedManifest.edgeCount * 4, "out-weights.bin")
        try Self.requireSize(inOffsetsData, (loadedManifest.nodeCount + 1) * 8, "in-offsets.bin")
        try Self.requireSize(inSourcesData, loadedManifest.edgeCount * 4, "in-sources.bin")
        try Self.requireSize(inWeightsData, loadedManifest.edgeCount * 4, "in-weights.bin")

        guard Self.readUInt64(outOffsetsData, element: 0) == 0,
              Self.readUInt64(outOffsetsData, element: loadedManifest.nodeCount) == UInt64(loadedManifest.edgeCount),
              Self.readUInt64(inOffsetsData, element: 0) == 0,
              Self.readUInt64(inOffsetsData, element: loadedManifest.nodeCount) == UInt64(loadedManifest.edgeCount) else {
            throw FullCNSGraphError.invalidBinary("offset 边界与 edgeCount 不一致")
        }
        try Self.requireMonotonicOffsets(
            outOffsetsData,
            nodeCount: loadedManifest.nodeCount,
            edgeCount: loadedManifest.edgeCount,
            name: "out-offsets.bin"
        )
        try Self.requireMonotonicOffsets(
            inOffsetsData,
            nodeCount: loadedManifest.nodeCount,
            edgeCount: loadedManifest.edgeCount,
            name: "in-offsets.bin"
        )
        try Self.requireIndicesInBounds(
            outTargetsData,
            nodeCount: loadedManifest.nodeCount,
            name: "out-targets.bin"
        )

        var roleMap: [UInt32: [UInt32]] = [:]
        for bit in loadedManifest.roleBits.values {
            roleMap[bit] = []
            roleMap[bit]?.reserveCapacity(loadedManifest.nodeCount / 16)
        }
        var leftDescending: [UInt32] = []
        var rightDescending: [UInt32] = []
        nodeData.withUnsafeBytes { rawBuffer in
            for index in 0..<loadedManifest.nodeCount {
                let offset = index * Self.nodeRecordBytes
                let flags = UInt32(littleEndian: rawBuffer.loadUnaligned(
                    fromByteOffset: offset + 8,
                    as: UInt32.self
                ))
                for bit in loadedManifest.roleBits.values where flags & bit != 0 {
                    roleMap[bit, default: []].append(UInt32(index))
                }
                guard flags & FullCNSNodeRole.descending.rawValue != 0 else { continue }
                switch rawBuffer[offset + 13] {
                case FullCNSHemisphere.left.rawValue: leftDescending.append(UInt32(index))
                case FullCNSHemisphere.right.rawValue: rightDescending.append(UInt32(index))
                default: break
                }
            }
        }
        self.directoryURL = directoryURL
        manifest = loadedManifest
        nodes = nodeData
        outgoingOffsets = outOffsetsData
        outgoingTargets = outTargetsData
        outgoingWeights = outWeightsData
        incomingOffsets = inOffsetsData
        incomingSources = inSourcesData
        incomingWeights = inWeightsData
        indicesByRoleBit = roleMap
        leftDescendingIndices = leftDescending
        rightDescendingIndices = rightDescending
    }

    public static func bundled() throws -> FullCNSGraph {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        let bundles = [bundle]
        #else
        let bundles = [Bundle(for: FullCNSGraph.self), Bundle.main]
        #endif
        let candidates = bundles.flatMap { bundle in
            [
                bundle.resourceURL?.appendingPathComponent("FullCNS", isDirectory: true),
                bundle.url(forResource: "FullCNS", withExtension: nil),
            ].compactMap { $0 }
        }
        guard let directory = candidates.first(where: {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent("manifest.json").path
            )
        }) else {
            throw FullCNSGraphError.missingResource("FullCNS/manifest.json")
        }
        return try FullCNSGraph(directoryURL: directory)
    }

    public var nodeCount: Int { manifest.nodeCount }
    public var edgeCount: Int { manifest.edgeCount }

    public func node(at index: Int) -> FullCNSNode {
        precondition(index >= 0 && index < manifest.nodeCount)
        let offset = index * Self.nodeRecordBytes
        return nodes.withUnsafeBytes { rawBuffer in
            let x = Int32(littleEndian: rawBuffer.loadUnaligned(
                fromByteOffset: offset + 16,
                as: Int32.self
            ))
            let y = Int32(littleEndian: rawBuffer.loadUnaligned(
                fromByteOffset: offset + 20,
                as: Int32.self
            ))
            let z = Int32(littleEndian: rawBuffer.loadUnaligned(
                fromByteOffset: offset + 24,
                as: Int32.self
            ))
            let confidenceBits = UInt32(littleEndian: rawBuffer.loadUnaligned(
                fromByteOffset: offset + 28,
                as: UInt32.self
            ))
            return FullCNSNode(
                bodyID: UInt64(littleEndian: rawBuffer.loadUnaligned(
                    fromByteOffset: offset,
                    as: UInt64.self
                )),
                roles: FullCNSNodeRole(rawValue: UInt32(littleEndian: rawBuffer.loadUnaligned(
                    fromByteOffset: offset + 8,
                    as: UInt32.self
                ))),
                transmitter: FullCNSNeurotransmitter(rawValue: rawBuffer[offset + 12]) ?? .unclear,
                hemisphere: FullCNSHemisphere(rawValue: rawBuffer[offset + 13]) ?? .unknown,
                traceQuality: rawBuffer[offset + 14],
                somaX: x == Self.missingCoordinate ? nil : x,
                somaY: y == Self.missingCoordinate ? nil : y,
                somaZ: z == Self.missingCoordinate ? nil : z,
                transmitterConfidence: Float(bitPattern: confidenceBits)
            )
        }
    }

    public func index(forBodyID bodyID: UInt64) -> Int? {
        var lowerBound = 0
        var upperBound = manifest.nodeCount
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            let candidate = Self.readBodyID(nodes, index: middle)
            if candidate < bodyID {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        guard lowerBound < manifest.nodeCount,
              Self.readBodyID(nodes, index: lowerBound) == bodyID else { return nil }
        return lowerBound
    }

    public func indices(with role: FullCNSNodeRole) -> [UInt32] {
        indicesByRoleBit[role.rawValue] ?? []
    }

    public func descendingIndices(in hemisphere: FullCNSHemisphere) -> [UInt32] {
        switch hemisphere {
        case .left: leftDescendingIndices
        case .right: rightDescendingIndices
        case .unknown, .midline: []
        }
    }

    public func outgoingEdgeRange(forNode index: Int) -> Range<Int> {
        precondition(index >= 0 && index < manifest.nodeCount)
        let start = Int(Self.readUInt64(outgoingOffsets, element: index))
        let end = Int(Self.readUInt64(outgoingOffsets, element: index + 1))
        return start..<end
    }

    public func incomingEdgeRange(forNode index: Int) -> Range<Int> {
        precondition(index >= 0 && index < manifest.nodeCount)
        let start = Int(Self.readUInt64(incomingOffsets, element: index))
        let end = Int(Self.readUInt64(incomingOffsets, element: index + 1))
        return start..<end
    }

    public func forEachOutgoingEdge(
        ofNode index: Int,
        _ body: (_ edgeIndex: Int, _ targetIndex: Int, _ weight: UInt32) -> Bool
    ) {
        let range = outgoingEdgeRange(forNode: index)
        outgoingTargets.withUnsafeBytes { targetBytes in
            outgoingWeights.withUnsafeBytes { weightBytes in
                for edge in range {
                    let target = UInt32(littleEndian: targetBytes.loadUnaligned(
                        fromByteOffset: edge * 4,
                        as: UInt32.self
                    ))
                    let weight = UInt32(littleEndian: weightBytes.loadUnaligned(
                        fromByteOffset: edge * 4,
                        as: UInt32.self
                    ))
                    if !body(edge, Int(target), weight) { break }
                }
            }
        }
    }

    public func validateDeep() throws -> FullCNSValidationReport {
        var bodyIDsAscending = true
        var previousBodyID: UInt64?
        for index in 0..<manifest.nodeCount {
            let bodyID = node(at: index).bodyID
            if let previousBodyID, bodyID <= previousBodyID {
                bodyIDsAscending = false
            }
            previousBodyID = bodyID
        }

        var zeroOut = 0
        var zeroIn = 0
        var maximumOut = 0
        var maximumIn = 0
        for index in 0..<manifest.nodeCount {
            let outgoingCount = Int(
                Self.readUInt64(outgoingOffsets, element: index + 1)
                    - Self.readUInt64(outgoingOffsets, element: index)
            )
            let incomingCount = Int(
                Self.readUInt64(incomingOffsets, element: index + 1)
                    - Self.readUInt64(incomingOffsets, element: index)
            )
            if outgoingCount == 0 { zeroOut += 1 }
            if incomingCount == 0 { zeroIn += 1 }
            maximumOut = max(maximumOut, outgoingCount)
            maximumIn = max(maximumIn, incomingCount)
        }

        var outgoingSum: UInt64 = 0
        var incomingSum: UInt64 = 0
        var targetsInBounds = true
        var sourcesInBounds = true
        outgoingTargets.withUnsafeBytes { targetBytes in
            outgoingWeights.withUnsafeBytes { weightBytes in
                for edge in 0..<manifest.edgeCount {
                    let target = UInt32(littleEndian: targetBytes.loadUnaligned(
                        fromByteOffset: edge * 4,
                        as: UInt32.self
                    ))
                    let weight = UInt32(littleEndian: weightBytes.loadUnaligned(
                        fromByteOffset: edge * 4,
                        as: UInt32.self
                    ))
                    targetsInBounds = targetsInBounds && Int(target) < manifest.nodeCount
                    outgoingSum += UInt64(weight)
                }
            }
        }
        incomingSources.withUnsafeBytes { sourceBytes in
            incomingWeights.withUnsafeBytes { weightBytes in
                for edge in 0..<manifest.edgeCount {
                    let source = UInt32(littleEndian: sourceBytes.loadUnaligned(
                        fromByteOffset: edge * 4,
                        as: UInt32.self
                    ))
                    let weight = UInt32(littleEndian: weightBytes.loadUnaligned(
                        fromByteOffset: edge * 4,
                        as: UInt32.self
                    ))
                    sourcesInBounds = sourcesInBounds && Int(source) < manifest.nodeCount
                    incomingSum += UInt64(weight)
                }
            }
        }
        guard outgoingSum == manifest.synapseWeightSum,
              incomingSum == manifest.synapseWeightSum else {
            throw FullCNSGraphError.invalidBinary("突触总量与 manifest 不一致")
        }

        let dataByName = [
            "nodes.bin": nodes,
            "out-offsets.bin": outgoingOffsets,
            "out-targets.bin": outgoingTargets,
            "out-weights.bin": outgoingWeights,
            "in-offsets.bin": incomingOffsets,
            "in-sources.bin": incomingSources,
            "in-weights.bin": incomingWeights,
        ]
        let expectedFileOrder = [
            "nodes.bin",
            "out-offsets.bin",
            "out-targets.bin",
            "out-weights.bin",
            "in-offsets.bin",
            "in-sources.bin",
            "in-weights.bin",
        ]
        guard manifest.files.map(\.name) == expectedFileOrder else {
            throw FullCNSGraphError.invalidManifest("文件清单或顺序与格式定义不一致")
        }
        var graphHasher = SHA256()
        for record in manifest.files {
            guard let data = dataByName[record.name], data.count == record.bytes else {
                throw FullCNSGraphError.invalidBinary("\(record.name) 与 manifest 大小不一致")
            }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex == record.sha256 else {
                throw FullCNSGraphError.invalidBinary("\(record.name) SHA-256 不匹配")
            }
            graphHasher.update(data: Data(digest))
        }
        let computedGraphSHA256 = graphHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        guard computedGraphSHA256 == manifest.graphSha256,
              computedGraphSHA256 == Self.pinnedGraphSHA256 else {
            throw FullCNSGraphError.invalidBinary("图 SHA-256 与 v1.0 固定产物不一致")
        }
        return FullCNSValidationReport(
            nodeCount: manifest.nodeCount,
            edgeCount: manifest.edgeCount,
            synapseWeightSum: outgoingSum,
            incomingSynapseWeightSum: incomingSum,
            zeroOutDegreeNodeCount: zeroOut,
            zeroInDegreeNodeCount: zeroIn,
            maximumOutDegree: maximumOut,
            maximumInDegree: maximumIn,
            bodyIDsStrictlyAscending: bodyIDsAscending,
            targetsInBounds: targetsInBounds,
            sourcesInBounds: sourcesInBounds,
            fileChecksumsMatch: true,
            graphChecksumMatchesPinnedArtifact: true
        )
    }

    private static func map(_ name: String, in directory: URL) throws -> Data {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FullCNSGraphError.missingResource(name)
        }
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw FullCNSGraphError.invalidBinary("\(name)：\(error.localizedDescription)")
        }
    }

    private static func requireSize(_ data: Data, _ expected: Int, _ name: String) throws {
        guard data.count == expected else {
            throw FullCNSGraphError.invalidBinary(
                "\(name) 应为 \(expected) bytes，实际为 \(data.count) bytes"
            )
        }
    }

    private static func requireMonotonicOffsets(
        _ data: Data,
        nodeCount: Int,
        edgeCount: Int,
        name: String
    ) throws {
        var previous: UInt64 = 0
        for index in 0...nodeCount {
            let current = readUInt64(data, element: index)
            guard current >= previous, current <= UInt64(edgeCount) else {
                throw FullCNSGraphError.invalidBinary("\(name) 不是合法的单调 offset 序列")
            }
            previous = current
        }
    }

    private static func requireIndicesInBounds(
        _ data: Data,
        nodeCount: Int,
        name: String
    ) throws {
        let isValid = data.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: data.count, by: 4) {
                let index = UInt32(littleEndian: bytes.loadUnaligned(
                    fromByteOffset: offset,
                    as: UInt32.self
                ))
                if Int(index) >= nodeCount { return false }
            }
            return true
        }
        guard isValid else {
            throw FullCNSGraphError.invalidBinary("\(name) 包含越界节点索引")
        }
    }

    private static func readUInt64(_ data: Data, element: Int) -> UInt64 {
        data.withUnsafeBytes {
            UInt64(littleEndian: $0.loadUnaligned(
                fromByteOffset: element * 8,
                as: UInt64.self
            ))
        }
    }

    private static func readBodyID(_ data: Data, index: Int) -> UInt64 {
        data.withUnsafeBytes {
            UInt64(littleEndian: $0.loadUnaligned(
                fromByteOffset: index * nodeRecordBytes,
                as: UInt64.self
            ))
        }
    }
}
