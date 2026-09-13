import CyberFlyCore
import Foundation

enum MaleCNSLearningSide: String, Sendable {
    case left
    case right
    case unknown
}

struct MaleCNSLearningKenyonDefinition: Sendable {
    let bodyID: Int64
    let cellType: String
    let side: MaleCNSLearningSide
    let dm1InputSynapses: Int
    let dm2InputSynapses: Int
    let avoidanceOutputSynapses: Int
    let approachOutputSynapses: Int
}

public struct KCPlasticityState: Codable, Equatable, Sendable {
    public let bodyID: Int64
    public var avoidanceEfficacy: Double
    public var approachEfficacy: Double

    public init(
        bodyID: Int64,
        avoidanceEfficacy: Double = 1,
        approachEfficacy: Double = 1
    ) {
        self.bodyID = bodyID
        self.avoidanceEfficacy = Self.clamp(avoidanceEfficacy)
        self.approachEfficacy = Self.clamp(approachEfficacy)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.18), 1)
    }
}

public struct MaleCNSLearningMemory: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let individualID: UUID
    public let datasetID: String
    public let circuitID: String
    public let updatedAt: Date
    public let revision: UInt64
    public let kenyonPlasticity: [KCPlasticityState]

    public init(
        schemaVersion: Int = MaleCNSLearningMemory.currentSchemaVersion,
        individualID: UUID,
        datasetID: String,
        circuitID: String,
        updatedAt: Date,
        revision: UInt64,
        kenyonPlasticity: [KCPlasticityState]
    ) {
        self.schemaVersion = schemaVersion
        self.individualID = individualID
        self.datasetID = datasetID
        self.circuitID = circuitID
        self.updatedAt = updatedAt
        self.revision = revision
        self.kenyonPlasticity = kenyonPlasticity
    }
}

public final class MaleCNSLearningMemoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.fileManager = .default
    }

    public func load(
        matching individualID: UUID,
        allowingLegacyMigration: Bool = false
    ) throws -> PersistentLoadResult<MaleCNSLearningMemory> {
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
            let memory = try decoder.decode(MaleCNSLearningMemory.self, from: data)
            guard memory.schemaVersion == MaleCNSLearningMemory.currentSchemaVersion else {
                throw MemoryValidationError.unsupportedSchema(memory.schemaVersion)
            }
            guard memory.individualID == individualID else {
                throw MemoryValidationError.individualMismatch(
                    expected: individualID,
                    actual: memory.individualID
                )
            }
            try validate(memory)
            return .loaded(memory)
        } catch {
            if allowingLegacyMigration,
               let legacy = try? decoder.decode(LegacyMaleCNSLearningMemory.self, from: data),
               legacy.schemaVersion == 1 {
                let migrated = MaleCNSLearningMemory(
                    individualID: individualID,
                    datasetID: legacy.datasetID,
                    circuitID: legacy.circuitID,
                    updatedAt: legacy.updatedAt,
                    revision: legacy.revision,
                    kenyonPlasticity: legacy.kenyonPlasticity
                )
                do {
                    try validate(migrated)
                    return .loaded(migrated)
                } catch {
                    return try quarantine(dataError: error)
                }
            }
            return try quarantine(dataError: error)
        }
    }

    public func save(_ memory: MaleCNSLearningMemory) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(memory)
        try data.write(to: fileURL, options: .atomic)
    }

    public static func nextToSnapshot(_ snapshotURL: URL) -> MaleCNSLearningMemoryStore {
        MaleCNSLearningMemoryStore(
            fileURL: snapshotURL.deletingLastPathComponent()
                .appendingPathComponent("learning-memory.json")
        )
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

    private func validate(_ memory: MaleCNSLearningMemory) throws {
        guard memory.datasetID == MaleCNSLearningCircuit.datasetID,
              memory.circuitID == MaleCNSLearningCircuit.circuitID else {
            throw MemoryValidationError.circuitMismatch
        }
        let expectedIDs = Set(GeneratedMaleCNSLearningCircuitData.kenyonCells.map(\.bodyID))
        let states = memory.kenyonPlasticity
        let actualIDs = Set(states.map(\.bodyID))
        guard states.count == expectedIDs.count,
              actualIDs == expectedIDs else {
            throw MemoryValidationError.invalidKenyonIdentities
        }
        guard states.allSatisfy({
            $0.avoidanceEfficacy.isFinite
                && $0.approachEfficacy.isFinite
                && (0.18...1).contains($0.avoidanceEfficacy)
                && (0.18...1).contains($0.approachEfficacy)
        }) else {
            throw MemoryValidationError.invalidPlasticity
        }
    }

    private func quarantine(
        dataError: Error
    ) throws -> PersistentLoadResult<MaleCNSLearningMemory> {
        let reason = dataError.localizedDescription
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

private struct LegacyMaleCNSLearningMemory: Codable {
    let schemaVersion: Int
    let datasetID: String
    let circuitID: String
    let updatedAt: Date
    let revision: UInt64
    let kenyonPlasticity: [KCPlasticityState]
}

private enum MemoryValidationError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case individualMismatch(expected: UUID, actual: UUID)
    case circuitMismatch
    case invalidKenyonIdentities
    case invalidPlasticity

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "不支持的记忆格式版本：\(version)"
        case let .individualMismatch(expected, actual):
            "记忆个体不匹配，期望 \(expected.uuidString)，实际 \(actual.uuidString)"
        case .circuitMismatch:
            "记忆对应的数据集或学习回路不匹配"
        case .invalidKenyonIdentities:
            "记忆中的 Kenyon cell 身份不完整或重复"
        case .invalidPlasticity:
            "记忆中的突触可塑性数值无效"
        }
    }
}

public struct MaleCNSLearningOutput: Equatable, Sendable {
    public let datasetID: String
    public let circuitID: String
    public let realNeuronCount: Int
    public let kenyonCellCount: Int
    public let activeKenyonCellCount: Int
    public let currentCue: FlyOdorCue?
    public let currentLearnedValence: Double
    public let currentMemoryConfidence: Double
    public let strongestMemoryCue: FlyOdorCue?
    public let strongestMemoryValence: Double
    public let strongestMemoryConfidence: Double
    public let rewardDANActivity: Double
    public let punishmentDANActivity: Double
    public let approachMBONActivity: Double
    public let avoidanceMBONActivity: Double
    public let memorySummary: String

    static var silent: MaleCNSLearningOutput {
        MaleCNSLearningOutput(
            datasetID: GeneratedMaleCNSLearningCircuitData.datasetID,
            circuitID: GeneratedMaleCNSLearningCircuitData.circuitID,
            realNeuronCount: GeneratedMaleCNSLearningCircuitData.realNeuronCount,
            kenyonCellCount: GeneratedMaleCNSLearningCircuitData.kenyonCells.count,
            activeKenyonCellCount: 0,
            currentCue: nil,
            currentLearnedValence: 0,
            currentMemoryConfidence: 0,
            strongestMemoryCue: nil,
            strongestMemoryValence: 0,
            strongestMemoryConfidence: 0,
            rewardDANActivity: 0,
            punishmentDANActivity: 0,
            approachMBONActivity: 0,
            avoidanceMBONActivity: 0,
            memorySummary: "尚未形成气味联想"
        )
    }
}

public struct MaleCNSLearningCircuit: Sendable {
    public static let datasetID = GeneratedMaleCNSLearningCircuitData.datasetID
    public static let circuitID = GeneratedMaleCNSLearningCircuitData.circuitID
    public static let realNeuronCount = GeneratedMaleCNSLearningCircuitData.realNeuronCount
    public static let kenyonCellCount = GeneratedMaleCNSLearningCircuitData.kenyonCells.count
    public static let sourceSHA256 = GeneratedMaleCNSLearningCircuitData.sourceSHA256
    public static let populationCounts = GeneratedMaleCNSLearningCircuitData.populationCounts
    public static let pathwaySynapseCounts = GeneratedMaleCNSLearningCircuitData.pathwaySynapseCounts

    private static let sparseFraction = 0.05
    private static let minimumEfficacy = 0.18
    private static let rewardLearningRate = 0.22
    private static let punishmentLearningRate = 0.38
    private static let oppositeMemoryExtinctionRate = 0.09

    public let individualID: UUID
    private let cells: [MaleCNSLearningKenyonDefinition]
    private let maximumDM1Input: Double
    private let maximumDM2Input: Double
    private let plasticityEnabled: Bool
    private var avoidanceEfficacy: [Double]
    private var approachEfficacy: [Double]
    public private(set) var memoryRevision: UInt64

    public init(
        individualID: UUID? = nil,
        memory: MaleCNSLearningMemory? = nil,
        plasticityEnabled: Bool = true
    ) {
        let cells = GeneratedMaleCNSLearningCircuitData.kenyonCells
        let resolvedIndividualID = individualID ?? memory?.individualID ?? UUID()
        self.individualID = resolvedIndividualID
        self.cells = cells
        self.maximumDM1Input = Double(cells.map(\.dm1InputSynapses).max() ?? 1)
        self.maximumDM2Input = Double(cells.map(\.dm2InputSynapses).max() ?? 1)
        self.plasticityEnabled = plasticityEnabled

        let restored: [Int64: KCPlasticityState]
        if let memory,
           memory.schemaVersion == MaleCNSLearningMemory.currentSchemaVersion,
           memory.individualID == resolvedIndividualID,
           memory.datasetID == Self.datasetID,
           memory.circuitID == Self.circuitID {
            restored = Dictionary(
                memory.kenyonPlasticity.map { ($0.bodyID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            self.memoryRevision = memory.revision
        } else {
            restored = [:]
            self.memoryRevision = 0
        }
        self.avoidanceEfficacy = cells.map {
            Self.clampEfficacy(restored[$0.bodyID]?.avoidanceEfficacy ?? 1)
        }
        self.approachEfficacy = cells.map {
            Self.clampEfficacy(restored[$0.bodyID]?.approachEfficacy ?? 1)
        }
    }

    public mutating func step(
        amberOdor: Double,
        berryOdor: Double,
        rewardSignal: Double = 0,
        punishmentSignal: Double = 0,
        deltaTime rawDeltaTime: TimeInterval
    ) -> MaleCNSLearningOutput {
        let deltaTime = min(max(rawDeltaTime, 0.001), 1)
        let amber = Self.clamp(amberOdor)
        let berry = Self.clamp(berryOdor)
        let reward = Self.clamp(rewardSignal)
        let punishment = Self.clamp(punishmentSignal)
        let active = activeKenyonCells(amberOdor: amber, berryOdor: berry)

        if plasticityEnabled,
           !active.isEmpty,
           (reward > 0 || punishment > 0) {
            applyPlasticity(
                active: active,
                reward: reward,
                punishment: punishment,
                deltaTime: deltaTime
            )
            memoryRevision &+= 1
        }

        let currentReadout = readout(active: active)
        let amberReadout = readout(active: activeKenyonCells(amberOdor: 1, berryOdor: 0))
        let berryReadout = readout(active: activeKenyonCells(amberOdor: 0, berryOdor: 1))
        let strongest = strongestMemory(amber: amberReadout, berry: berryReadout)
        let currentCue = dominantCue(amberOdor: amber, berryOdor: berry)

        return MaleCNSLearningOutput(
            datasetID: Self.datasetID,
            circuitID: Self.circuitID,
            realNeuronCount: Self.realNeuronCount,
            kenyonCellCount: Self.kenyonCellCount,
            activeKenyonCellCount: active.count,
            currentCue: currentCue,
            currentLearnedValence: currentCue == nil ? 0 : currentReadout.valence,
            currentMemoryConfidence: currentCue == nil ? 0 : currentReadout.confidence,
            strongestMemoryCue: strongest.cue,
            strongestMemoryValence: strongest.readout.valence,
            strongestMemoryConfidence: strongest.readout.confidence,
            rewardDANActivity: reward,
            punishmentDANActivity: punishment,
            approachMBONActivity: currentReadout.approach,
            avoidanceMBONActivity: currentReadout.avoidance,
            memorySummary: currentCue == nil
                ? summary(
                    cue: strongest.cue,
                    valence: strongest.readout.valence,
                    confidence: strongest.readout.confidence
                )
                : summary(
                    cue: currentCue,
                    valence: currentReadout.valence,
                    confidence: currentReadout.confidence
                )
        )
    }

    public func read(
        amberOdor: Double,
        berryOdor: Double
    ) -> MaleCNSLearningOutput {
        var readOnlyCopy = self
        return readOnlyCopy.step(
            amberOdor: amberOdor,
            berryOdor: berryOdor,
            deltaTime: 0.001
        )
    }

    public func exportMemory(now: Date = Date()) -> MaleCNSLearningMemory {
        MaleCNSLearningMemory(
            individualID: individualID,
            datasetID: Self.datasetID,
            circuitID: Self.circuitID,
            updatedAt: now,
            revision: memoryRevision,
            kenyonPlasticity: cells.indices.map { index in
                KCPlasticityState(
                    bodyID: cells[index].bodyID,
                    avoidanceEfficacy: avoidanceEfficacy[index],
                    approachEfficacy: approachEfficacy[index]
                )
            }
        )
    }

    private func activeKenyonCells(
        amberOdor: Double,
        berryOdor: Double
    ) -> [(index: Int, activity: Double)] {
        let intensity = max(amberOdor, berryOdor)
        guard intensity > 0.01 else { return [] }

        var scored: [(index: Int, score: Double)] = []
        scored.reserveCapacity(cells.count)
        for (index, cell) in cells.enumerated() {
            let dm1 = Double(cell.dm1InputSynapses) / max(maximumDM1Input, 1)
            let dm2 = Double(cell.dm2InputSynapses) / max(maximumDM2Input, 1)
            let input = dm1 * amberOdor + dm2 * berryOdor
            guard input > 0 else { continue }
            let intrinsic = deterministicExcitability(bodyID: cell.bodyID)
            scored.append((index, input + intrinsic * 0.035 * intensity))
        }
        scored.sort { $0.score > $1.score }
        let activeCount = min(
            scored.count,
            max(1, Int((Double(cells.count) * Self.sparseFraction).rounded()))
        )
        let peak = max(scored.first?.score ?? 1, 0.0001)
        return scored.prefix(activeCount).map { item in
            (
                index: item.index,
                activity: intensity * (0.55 + 0.45 * item.score / peak)
            )
        }
    }

    private mutating func applyPlasticity(
        active: [(index: Int, activity: Double)],
        reward: Double,
        punishment: Double,
        deltaTime: Double
    ) {
        for item in active {
            let index = item.index
            if reward > 0 {
                let depression = Self.rewardLearningRate * reward * item.activity * deltaTime
                avoidanceEfficacy[index] = Self.clampEfficacy(
                    avoidanceEfficacy[index] - depression
                )
                approachEfficacy[index] += (1 - approachEfficacy[index])
                    * Self.oppositeMemoryExtinctionRate * reward * deltaTime
            }
            if punishment > 0 {
                let depression = Self.punishmentLearningRate * punishment * item.activity * deltaTime
                approachEfficacy[index] = Self.clampEfficacy(
                    approachEfficacy[index] - depression
                )
                avoidanceEfficacy[index] += (1 - avoidanceEfficacy[index])
                    * Self.oppositeMemoryExtinctionRate * punishment * deltaTime
            }
            avoidanceEfficacy[index] = Self.clampEfficacy(avoidanceEfficacy[index])
            approachEfficacy[index] = Self.clampEfficacy(approachEfficacy[index])
        }
    }

    private func readout(
        active: [(index: Int, activity: Double)]
    ) -> (approach: Double, avoidance: Double, valence: Double, confidence: Double) {
        guard !active.isEmpty else { return (0, 0, 0, 0) }
        var approachBaseline = 0.0
        var avoidanceBaseline = 0.0
        var approachEffective = 0.0
        var avoidanceEffective = 0.0

        for item in active {
            let cell = cells[item.index]
            let approachWeight = Double(cell.approachOutputSynapses) * item.activity
            let avoidanceWeight = Double(cell.avoidanceOutputSynapses) * item.activity
            approachBaseline += approachWeight
            avoidanceBaseline += avoidanceWeight
            approachEffective += approachWeight * approachEfficacy[item.index]
            avoidanceEffective += avoidanceWeight * avoidanceEfficacy[item.index]
        }

        let approach = approachBaseline > 0 ? approachEffective / approachBaseline : 1
        let avoidance = avoidanceBaseline > 0 ? avoidanceEffective / avoidanceBaseline : 1
        let valence = Self.clampSigned((approach - avoidance) * 1.75)
        let confidence = Self.clamp(max(1 - approach, 1 - avoidance))
        return (approach, avoidance, valence, confidence)
    }

    private func strongestMemory(
        amber: (approach: Double, avoidance: Double, valence: Double, confidence: Double),
        berry: (approach: Double, avoidance: Double, valence: Double, confidence: Double)
    ) -> (
        cue: FlyOdorCue?,
        readout: (approach: Double, avoidance: Double, valence: Double, confidence: Double)
    ) {
        let strongest = amber.confidence >= berry.confidence
            ? (FlyOdorCue.amber, amber)
            : (FlyOdorCue.berry, berry)
        return strongest.1.confidence < 0.015 ? (nil, strongest.1) : strongest
    }

    private func dominantCue(amberOdor: Double, berryOdor: Double) -> FlyOdorCue? {
        guard max(amberOdor, berryOdor) > 0.01 else { return nil }
        return amberOdor >= berryOdor ? .amber : .berry
    }

    private func summary(cue: FlyOdorCue?, valence: Double, confidence: Double) -> String {
        guard let cue, confidence >= 0.015 else { return "尚未形成气味联想" }
        if valence > 0.06 {
            return "记得\(cue.displayName)通常带来食物"
        }
        if valence < -0.06 {
            return "记得\(cue.displayName)曾伴随威胁"
        }
        return "对\(cue.displayName)保留着矛盾记忆"
    }

    private func deterministicExcitability(bodyID: Int64) -> Double {
        var value = UInt64(bitPattern: bodyID)
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value & 0xFFFF) / Double(0xFFFF)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }

    private static func clampEfficacy(_ value: Double) -> Double {
        min(max(value, minimumEfficacy), 1)
    }
}
