import Foundation

public struct FullCNSPersistentState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let individualID: UUID
    public let graphSHA256: String
    public let nodeCount: Int
    public let updatedAt: Date
    public let cumulativeSimulatedSeconds: Double
    public let globalCursor: Int
    public let cohortCursors: [String: Int]
    public let homeostaticThreshold: Float
    public let dopamineLevel: Float
    public let serotoninLevel: Float
    public let octopamineLevel: Float
    public let membrane: [Float]
    public let activity: [Float]
    public let presynapticEligibility: [Float]

    func validate(graphSHA256 expectedGraphSHA256: String, nodeCount expectedNodeCount: Int) throws {
        guard graphSHA256 == expectedGraphSHA256, nodeCount == expectedNodeCount else {
            throw FullCNSStateError.graphMismatch
        }
        guard membrane.count == expectedNodeCount,
              activity.count == expectedNodeCount,
              presynapticEligibility.count == expectedNodeCount else {
            throw FullCNSStateError.invalidArrayLengths
        }
        let scalarValues = [
            homeostaticThreshold,
            dopamineLevel,
            serotoninLevel,
            octopamineLevel,
        ]
        guard updatedAt.timeIntervalSinceReferenceDate.isFinite,
              cumulativeSimulatedSeconds.isFinite,
              cumulativeSimulatedSeconds >= 0,
              scalarValues.allSatisfy(\.isFinite),
              (0.72...1.35).contains(homeostaticThreshold),
              (0...1).contains(dopamineLevel),
              (0...1).contains(serotoninLevel),
              (0...1).contains(octopamineLevel),
              globalCursor >= 0,
              globalCursor < expectedNodeCount,
              cohortCursors.allSatisfy({ key, value in
                  guard let parsedKey = UInt32(key) else { return false }
                  return String(parsedKey) == key
                      && value >= 0
                      && value < expectedNodeCount
              }),
              membrane.allSatisfy({ $0.isFinite && (-2.5...2.5).contains($0) }),
              activity.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              presynapticEligibility.allSatisfy({
                  $0.isFinite && (-0.35...0.35).contains($0)
              }) else {
            throw FullCNSStateError.invalidValue
        }
    }
}

public enum FullCNSStateError: Error, LocalizedError {
    case unsupportedSchema(Int)
    case individualMismatch
    case graphMismatch
    case invalidArrayLengths
    case invalidValue

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version): "不支持的全 CNS 状态版本：\(version)"
        case .individualMismatch: "全 CNS 状态属于另一只果蝇"
        case .graphMismatch: "全 CNS 状态与当前连接组不匹配"
        case .invalidArrayLengths: "全 CNS 状态的神经元数组不完整"
        case .invalidValue: "全 CNS 状态包含非法数值"
        }
    }
}

public struct FullCNSSensoryInput: Codable, Equatable, Sendable {
    public var leftVisualMotion: Double
    public var rightVisualMotion: Double
    public var odor: Double
    public var taste: Double
    public var touch: Double
    public var proprioception: Double
    public var hunger: Double
    public var reward: Double
    public var punishment: Double

    public init(
        leftVisualMotion: Double = 0,
        rightVisualMotion: Double = 0,
        odor: Double = 0,
        taste: Double = 0,
        touch: Double = 0,
        proprioception: Double = 0,
        hunger: Double = 0,
        reward: Double = 0,
        punishment: Double = 0
    ) {
        self.leftVisualMotion = Self.clamp(leftVisualMotion)
        self.rightVisualMotion = Self.clamp(rightVisualMotion)
        self.odor = Self.clamp(odor)
        self.taste = Self.clamp(taste)
        self.touch = Self.clamp(touch)
        self.proprioception = Self.clamp(proprioception)
        self.hunger = Self.clamp(hunger)
        self.reward = Self.clamp(reward)
        self.punishment = Self.clamp(punishment)
    }

    public static let quiet = FullCNSSensoryInput()

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct FullCNSRuntimeConfiguration: Equatable, Sendable {
    public var biologicalTimeStep: Double
    public var maximumSubstepsPerCall: Int
    public var maximumEdgeEventsPerCall: Int
    public var maximumSeedsPerCohortPerSubstep: Int
    public var membraneDecayPerSubstep: Float
    public var activityDecayPerSubstep: Float
    public var synapticGain: Float
    public var baseThreshold: Float
    public var spontaneousSpikesPerSubstep: Int
    public var homeostaticTargetActiveFraction: Float
    public var plasticityRate: Float

    public init(
        biologicalTimeStep: Double = 0.01,
        maximumSubstepsPerCall: Int = 50,
        maximumEdgeEventsPerCall: Int = 150_000,
        maximumSeedsPerCohortPerSubstep: Int = 2,
        membraneDecayPerSubstep: Float = 0.91,
        activityDecayPerSubstep: Float = 0.89,
        synapticGain: Float = 0.18,
        baseThreshold: Float = 1,
        spontaneousSpikesPerSubstep: Int = 1,
        homeostaticTargetActiveFraction: Float = 0.012,
        plasticityRate: Float = 0.0025
    ) {
        self.biologicalTimeStep = max(biologicalTimeStep, 0.001)
        self.maximumSubstepsPerCall = max(maximumSubstepsPerCall, 1)
        self.maximumEdgeEventsPerCall = max(maximumEdgeEventsPerCall, 1)
        self.maximumSeedsPerCohortPerSubstep = max(maximumSeedsPerCohortPerSubstep, 1)
        self.membraneDecayPerSubstep = min(max(membraneDecayPerSubstep, 0), 1)
        self.activityDecayPerSubstep = min(max(activityDecayPerSubstep, 0), 1)
        self.synapticGain = max(synapticGain, 0)
        self.baseThreshold = max(baseThreshold, 0.01)
        self.spontaneousSpikesPerSubstep = max(spontaneousSpikesPerSubstep, 0)
        self.homeostaticTargetActiveFraction = min(max(homeostaticTargetActiveFraction, 0), 1)
        self.plasticityRate = max(plasticityRate, 0)
    }

    public static let standard = FullCNSRuntimeConfiguration()
}

public struct FullCNSRuntimeMetrics: Equatable, Sendable {
    public let dataset: String
    public let graphSha256: String
    public let nodeCount: Int
    public let edgeCount: Int
    public let simulatedSeconds: Double
    public let wallSeconds: Double
    public let realTimeFactor: Double
    public let substeps: Int
    public let spikeCount: Int
    public let edgeEventCount: Int
    public let activeNeuronCount: Int
    public let meanActivity: Double
    public let sensoryActivity: Double
    public let centralComplexActivity: Double
    public let descendingActivity: Double
    public let motorActivity: Double
    public let leftDescendingActivity: Double
    public let rightDescendingActivity: Double
    public let turnBias: Double
    public let dopamineLevel: Double
    public let serotoninLevel: Double
    public let octopamineLevel: Double
    public let homeostaticThreshold: Double
    public let plasticSynapseSourceCount: Int
    public let silencedNeuronCount: Int
    public let stimulatedNeuronCount: Int
    public let eventBudgetSaturated: Bool

    public static func idle(graph: FullCNSGraph) -> FullCNSRuntimeMetrics {
        FullCNSRuntimeMetrics(
            dataset: graph.manifest.dataset,
            graphSha256: graph.manifest.graphSha256,
            nodeCount: graph.nodeCount,
            edgeCount: graph.edgeCount,
            simulatedSeconds: 0,
            wallSeconds: 0,
            realTimeFactor: 0,
            substeps: 0,
            spikeCount: 0,
            edgeEventCount: 0,
            activeNeuronCount: 0,
            meanActivity: 0,
            sensoryActivity: 0,
            centralComplexActivity: 0,
            descendingActivity: 0,
            motorActivity: 0,
            leftDescendingActivity: 0,
            rightDescendingActivity: 0,
            turnBias: 0,
            dopamineLevel: 0,
            serotoninLevel: 0,
            octopamineLevel: 0,
            homeostaticThreshold: 1,
            plasticSynapseSourceCount: 0,
            silencedNeuronCount: 0,
            stimulatedNeuronCount: 0,
            eventBudgetSaturated: false
        )
    }
}

/// Event-driven full-CNS emulator. Every traced neuron owns state, while work is
/// proportional to actual spikes rather than scanning all 25.6M edges per tick.
/// Membrane dynamics, transmitter signs and plasticity are explicitly modeled
/// (`literature`/`fitted`/`assumed`), never relabelled as MaleCNS observations.
public final class FullCNSRuntime: @unchecked Sendable {
    public static let modelID = "male-cns-whole-cns-v1.0"
    public static let provenance = "observed graph + predicted NT + modeled dynamics"

    public let graph: FullCNSGraph
    public let configuration: FullCNSRuntimeConfiguration

    private static let visualAnnotations: [UInt64: (type: String, instance: String)] =
        Dictionary(uniqueKeysWithValues: GeneratedMaleCNSVisualCircuitData.neurons.map {
            (UInt64($0.bodyID), ($0.cellType, $0.instance))
        })
    private static let learningAnnotations: [UInt64: String] =
        Dictionary(uniqueKeysWithValues: GeneratedMaleCNSLearningCircuitData.kenyonCells.map {
            (UInt64($0.bodyID), $0.cellType)
        })

    private var membrane: [Float]
    private var activity: [Float]
    private var spikeGeneration: [UInt32]
    private var generation: UInt32 = 0
    private var cohortCursors: [UInt32: Int] = [:]
    private var globalCursor = 0
    private var homeostaticThreshold: Float
    private var dopamineLevel: Float = 0
    private var serotoninLevel: Float = 0
    private var octopamineLevel: Float = 0
    private var presynapticEligibility: [Float]
    private var silenced: [Bool]
    private var stimulatedIndices: [UInt32] = []
    private var stimulationAmplitude: Float = 0
    private var cumulativeSimulatedSeconds: Double = 0

    private let sensoryIndices: [UInt32]
    private let visualLeftIndices: [UInt32]
    private let visualRightIndices: [UInt32]
    private let visualSteeringInputLeftIndices: [UInt32]
    private let visualSteeringInputRightIndices: [UInt32]
    private let steeringOutputLeftIndices: [UInt32]
    private let steeringOutputRightIndices: [UInt32]
    private let olfactoryIndices: [UInt32]
    private let gustatoryIndices: [UInt32]
    private let mechanosensoryIndices: [UInt32]
    private let ascendingIndices: [UInt32]
    private let centralComplexIndices: [UInt32]
    private let motorIndices: [UInt32]
    private let dopamineIndices: [UInt32]
    private let neurosecretoryIndices: [UInt32]
    private let leftDescendingIndices: [UInt32]
    private let rightDescendingIndices: [UInt32]

    public init(
        graph: FullCNSGraph,
        configuration: FullCNSRuntimeConfiguration = .standard
    ) {
        self.graph = graph
        self.configuration = configuration
        membrane = Array(repeating: 0, count: graph.nodeCount)
        activity = Array(repeating: 0, count: graph.nodeCount)
        spikeGeneration = Array(repeating: 0, count: graph.nodeCount)
        presynapticEligibility = Array(repeating: 0, count: graph.nodeCount)
        silenced = Array(repeating: false, count: graph.nodeCount)
        homeostaticThreshold = configuration.baseThreshold
        sensoryIndices = graph.indices(with: .sensory)
        olfactoryIndices = graph.indices(with: .olfactory)
        gustatoryIndices = graph.indices(with: .gustatory)
        mechanosensoryIndices = graph.indices(with: .mechanosensory)
        ascendingIndices = graph.indices(with: .ascending)
        centralComplexIndices = graph.indices(with: .centralComplex)
        motorIndices = graph.indices(with: .motor)
        dopamineIndices = graph.indices(with: .dopaminergic)
        neurosecretoryIndices = graph.indices(with: .neurosecretory)
        leftDescendingIndices = graph.descendingIndices(in: .left)
        rightDescendingIndices = graph.descendingIndices(in: .right)
        let visual = graph.indices(with: .visual)
        visualLeftIndices = visual.filter { graph.node(at: Int($0)).hemisphere == .left }
        visualRightIndices = visual.filter { graph.node(at: Int($0)).hemisphere == .right }
        visualSteeringInputLeftIndices = GeneratedMaleCNSVisualCircuitData.neurons.compactMap {
            guard $0.cellType == "LoVP92", $0.side == .left,
                  let index = graph.index(forBodyID: UInt64($0.bodyID)) else { return nil }
            return UInt32(index)
        }
        visualSteeringInputRightIndices = GeneratedMaleCNSVisualCircuitData.neurons.compactMap {
            guard $0.cellType == "LoVP92", $0.side == .right,
                  let index = graph.index(forBodyID: UInt64($0.bodyID)) else { return nil }
            return UInt32(index)
        }
        steeringOutputLeftIndices = GeneratedMaleCNSVisualCircuitData.neurons.compactMap {
            guard $0.cellType == "DNg13", $0.side == .left,
                  let index = graph.index(forBodyID: UInt64($0.bodyID)) else { return nil }
            return UInt32(index)
        }
        steeringOutputRightIndices = GeneratedMaleCNSVisualCircuitData.neurons.compactMap {
            guard $0.cellType == "DNg13", $0.side == .right,
                  let index = graph.index(forBodyID: UInt64($0.bodyID)) else { return nil }
            return UInt32(index)
        }
    }

    @discardableResult
    public func step(
        deltaTime rawDeltaTime: TimeInterval,
        input: FullCNSSensoryInput = .quiet
    ) -> FullCNSRuntimeMetrics {
        let started = ContinuousClock.now
        let requestedTime = min(max(rawDeltaTime, configuration.biologicalTimeStep), 0.5)
        let requestedSubsteps = Int(ceil(requestedTime / configuration.biologicalTimeStep))
        let substeps = min(requestedSubsteps, configuration.maximumSubstepsPerCall)
        let simulatedTime = Double(substeps) * configuration.biologicalTimeStep
        var spikeCount = 0
        var edgeEvents = 0
        var saturated = false

        for _ in 0..<substeps {
            generation &+= 1
            if generation == 0 {
                spikeGeneration = Array(repeating: 0, count: graph.nodeCount)
                generation = 1
            }
            for index in membrane.indices {
                membrane[index] *= configuration.membraneDecayPerSubstep
                activity[index] *= configuration.activityDecayPerSubstep
                presynapticEligibility[index] *= 0.9995
            }
            dopamineLevel *= 0.985
            serotoninLevel *= 0.993
            octopamineLevel *= 0.988

            var spikeQueue: [UInt32] = []
            spikeQueue.reserveCapacity(512)
            seed(
                visualLeftIndices,
                amplitude: input.leftVisualMotion,
                channel: FullCNSNodeRole.visual.rawValue | 0x10000,
                queue: &spikeQueue
            )
            seed(
                visualRightIndices,
                amplitude: input.rightVisualMotion,
                channel: FullCNSNodeRole.visual.rawValue | 0x20000,
                queue: &spikeQueue
            )
            seed(
                visualSteeringInputLeftIndices,
                amplitude: input.leftVisualMotion,
                channel: FullCNSNodeRole.visual.rawValue | 0x30000,
                queue: &spikeQueue
            )
            seed(
                visualSteeringInputRightIndices,
                amplitude: input.rightVisualMotion,
                channel: FullCNSNodeRole.visual.rawValue | 0x40000,
                queue: &spikeQueue
            )
            seed(olfactoryIndices, amplitude: input.odor, channel: FullCNSNodeRole.olfactory.rawValue, queue: &spikeQueue)
            seed(gustatoryIndices, amplitude: input.taste, channel: FullCNSNodeRole.gustatory.rawValue, queue: &spikeQueue)
            seed(mechanosensoryIndices, amplitude: input.touch, channel: FullCNSNodeRole.mechanosensory.rawValue, queue: &spikeQueue)
            seed(ascendingIndices, amplitude: input.proprioception, channel: FullCNSNodeRole.ascending.rawValue, queue: &spikeQueue)
            seed(neurosecretoryIndices, amplitude: input.hunger, channel: FullCNSNodeRole.neurosecretory.rawValue, queue: &spikeQueue)
            seed(dopamineIndices, amplitude: max(input.reward, input.punishment), channel: FullCNSNodeRole.dopaminergic.rawValue, queue: &spikeQueue)
            seedSpontaneousActivity(queue: &spikeQueue)
            seedStimulatedNeurons(queue: &spikeQueue)

            var queueIndex = 0
            while queueIndex < spikeQueue.count,
                  edgeEvents < configuration.maximumEdgeEventsPerCall {
                let sourceIndex = Int(spikeQueue[queueIndex])
                queueIndex += 1
                guard !silenced[sourceIndex] else { continue }
                spikeCount += 1
                activity[sourceIndex] = 1
                let source = graph.node(at: sourceIndex)
                updateModulator(for: source.transmitter, reward: input.reward, punishment: input.punishment)
                let sign = effectiveSign(for: source.transmitter)
                guard sign != 0 else { continue }
                if input.reward > 0 || input.punishment > 0 {
                    let valence = Float(input.reward - input.punishment)
                    presynapticEligibility[sourceIndex] = min(max(
                        presynapticEligibility[sourceIndex]
                            + valence * configuration.plasticityRate,
                        -0.35
                    ), 0.35)
                }

                graph.forEachOutgoingEdge(ofNode: sourceIndex) { _, targetIndex, weight in
                    guard edgeEvents < configuration.maximumEdgeEventsPerCall else { return false }
                    edgeEvents += 1
                    guard !silenced[targetIndex] else { return true }
                    let normalizedWeight = Float(log1p(Double(weight)) / log1p(Double(graph.manifest.maximumEdgeWeight)))
                    let learnedGain = 1 + presynapticEligibility[sourceIndex]
                    let modulation = 1 + dopamineLevel * 0.12 + octopamineLevel * 0.08
                    membrane[targetIndex] += sign
                        * normalizedWeight
                        * configuration.synapticGain
                        * learnedGain
                        * modulation
                    membrane[targetIndex] = min(max(membrane[targetIndex], -2.5), 2.5)

                    if membrane[targetIndex] >= homeostaticThreshold,
                       spikeGeneration[targetIndex] != generation {
                        spikeGeneration[targetIndex] = generation
                        membrane[targetIndex] = 0
                        spikeQueue.append(UInt32(targetIndex))
                    }
                    return true
                }
            }
            if queueIndex < spikeQueue.count {
                saturated = true
            }
        }

        cumulativeSimulatedSeconds += simulatedTime
        let activeNeuronCount = activity.reduce(into: 0) { count, value in
            if value >= 0.08 { count += 1 }
        }
        let plasticSourceCount = presynapticEligibility.reduce(into: 0) { count, value in
            if abs(value) >= 0.0001 { count += 1 }
        }
        let activeFraction = Float(activeNeuronCount) / Float(max(graph.nodeCount, 1))
        homeostaticThreshold += (activeFraction - configuration.homeostaticTargetActiveFraction) * 0.025
        homeostaticThreshold = min(max(homeostaticThreshold, 0.72), 1.35)

        let sensoryActivity = readoutActivity(in: sensoryIndices)
        let centralActivity = readoutActivity(in: centralComplexIndices)
        let motorActivity = readoutActivity(in: motorIndices)
        let leftDescending = readoutActivity(in: leftDescendingIndices)
        let rightDescending = readoutActivity(in: rightDescendingIndices)
        let descendingActivity = weightedMean(
            leftDescending,
            count: leftDescendingIndices.count,
            rightDescending,
            count: rightDescendingIndices.count
        )
        let mean = Double(activity.reduce(0, +)) / Double(max(activity.count, 1))
        let duration = started.duration(to: .now)
        let wallSeconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18

        let leftSteering = readoutActivity(in: steeringOutputLeftIndices)
        let rightSteering = readoutActivity(in: steeringOutputRightIndices)
        let steeringScale = max(leftSteering + rightSteering, 0.04)
        return FullCNSRuntimeMetrics(
            dataset: graph.manifest.dataset,
            graphSha256: graph.manifest.graphSha256,
            nodeCount: graph.nodeCount,
            edgeCount: graph.edgeCount,
            simulatedSeconds: simulatedTime,
            wallSeconds: wallSeconds,
            realTimeFactor: wallSeconds > 0 ? simulatedTime / wallSeconds : 0,
            substeps: substeps,
            spikeCount: spikeCount,
            edgeEventCount: edgeEvents,
            activeNeuronCount: activeNeuronCount,
            meanActivity: mean,
            sensoryActivity: sensoryActivity,
            centralComplexActivity: centralActivity,
            descendingActivity: descendingActivity,
            motorActivity: motorActivity,
            leftDescendingActivity: leftDescending,
            rightDescendingActivity: rightDescending,
            turnBias: min(max((rightSteering - leftSteering) / steeringScale, -1), 1),
            dopamineLevel: Double(dopamineLevel),
            serotoninLevel: Double(serotoninLevel),
            octopamineLevel: Double(octopamineLevel),
            homeostaticThreshold: Double(homeostaticThreshold),
            plasticSynapseSourceCount: plasticSourceCount,
            silencedNeuronCount: silenced.reduce(into: 0) { count, value in
                if value { count += 1 }
            },
            stimulatedNeuronCount: stimulatedIndices.count,
            eventBudgetSaturated: saturated
        )
    }

    public func resetDynamicState() {
        membrane = Array(repeating: 0, count: graph.nodeCount)
        activity = Array(repeating: 0, count: graph.nodeCount)
        spikeGeneration = Array(repeating: 0, count: graph.nodeCount)
        presynapticEligibility = Array(repeating: 0, count: graph.nodeCount)
        generation = 0
        cohortCursors.removeAll(keepingCapacity: true)
        globalCursor = 0
        homeostaticThreshold = configuration.baseThreshold
        dopamineLevel = 0
        serotoninLevel = 0
        octopamineLevel = 0
        cumulativeSimulatedSeconds = 0
    }

    @discardableResult
    public func setSilenced(bodyIDs: [UInt64]) -> Int {
        silenced = Array(repeating: false, count: graph.nodeCount)
        var count = 0
        for bodyID in Set(bodyIDs) {
            guard let index = graph.index(forBodyID: bodyID) else { continue }
            silenced[index] = true
            membrane[index] = 0
            activity[index] = 0
            count += 1
        }
        return count
    }

    @discardableResult
    public func setStimulated(bodyIDs: [UInt64], amplitude: Double = 1) -> Int {
        stimulatedIndices = Set(bodyIDs).compactMap {
            graph.index(forBodyID: $0).map(UInt32.init)
        }.sorted()
        stimulationAmplitude = Float(min(max(amplitude, 0), 1))
        return stimulatedIndices.count
    }

    public func clearPerturbations() {
        silenced = Array(repeating: false, count: graph.nodeCount)
        stimulatedIndices.removeAll(keepingCapacity: true)
        stimulationAmplitude = 0
    }

    public func inspectNeuron(bodyID: UInt64) -> FullCNSNeuronObservation? {
        guard let index = graph.index(forBodyID: bodyID) else { return nil }
        return neuronObservation(at: index)
    }

    public func inspectNeurons(
        matching query: FullCNSNeuronQuery
    ) -> [FullCNSNeuronObservation] {
        let search = query.bodyIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty,
           let exactBodyID = UInt64(search),
           String(exactBodyID) == search,
           let exact = inspectNeuron(bodyID: exactBodyID) {
            return matches(exact, query: query, search: search) ? [exact] : []
        }

        let candidates: [UInt32]
        if let role = query.role {
            candidates = graph.indices(with: role)
        } else {
            candidates = (0..<graph.nodeCount).map(UInt32.init)
        }

        var observations: [FullCNSNeuronObservation] = []
        observations.reserveCapacity(query.limit)
        for rawIndex in candidates {
            let observation = neuronObservation(at: Int(rawIndex))
            guard matches(observation, query: query, search: search) else { continue }
            observations.append(observation)
            if observations.count == query.limit { break }
        }
        return observations
    }

    private func neuronObservation(at index: Int) -> FullCNSNeuronObservation {
        let node = graph.node(at: index)
        let visualAnnotation = Self.visualAnnotations[node.bodyID]
        return FullCNSNeuronObservation(
            nodeIndex: index,
            bodyID: node.bodyID,
            annotationType: visualAnnotation?.type ?? Self.learningAnnotations[node.bodyID],
            annotationInstance: visualAnnotation?.instance,
            roles: node.roles,
            transmitter: node.transmitter,
            hemisphere: node.hemisphere,
            traceQuality: node.traceQuality,
            somaX: node.somaX,
            somaY: node.somaY,
            somaZ: node.somaZ,
            transmitterConfidence: Double(node.transmitterConfidence),
            outgoingEdgeCount: graph.outgoingEdgeRange(forNode: index).count,
            incomingEdgeCount: graph.incomingEdgeRange(forNode: index).count,
            membranePotential: Double(membrane[index]),
            activity: Double(activity[index]),
            presynapticEligibility: Double(presynapticEligibility[index]),
            isSilenced: silenced[index],
            isStimulated: stimulatedIndices.contains(UInt32(index)) && stimulationAmplitude > 0
        )
    }

    private func matches(
        _ observation: FullCNSNeuronObservation,
        query: FullCNSNeuronQuery,
        search: String
    ) -> Bool {
        if !search.isEmpty,
           !String(observation.bodyID).contains(search),
           !(observation.annotationType?.localizedCaseInsensitiveContains(search) ?? false),
           !(observation.annotationInstance?.localizedCaseInsensitiveContains(search) ?? false) {
            return false
        }
        if let role = query.role,
           !observation.roles.contains(role) {
            return false
        }
        if let transmitter = query.transmitter,
           observation.transmitter != transmitter {
            return false
        }
        if let hemisphere = query.hemisphere,
           observation.hemisphere != hemisphere {
            return false
        }
        return true
    }

    public func exportPersistentState(
        individualID: UUID,
        now: Date = Date()
    ) -> FullCNSPersistentState {
        FullCNSPersistentState(
            schemaVersion: FullCNSPersistentState.currentSchemaVersion,
            individualID: individualID,
            graphSHA256: graph.manifest.graphSha256,
            nodeCount: graph.nodeCount,
            updatedAt: now,
            cumulativeSimulatedSeconds: cumulativeSimulatedSeconds,
            globalCursor: globalCursor,
            cohortCursors: Dictionary(uniqueKeysWithValues: cohortCursors.map {
                (String($0.key), $0.value)
            }),
            homeostaticThreshold: homeostaticThreshold,
            dopamineLevel: dopamineLevel,
            serotoninLevel: serotoninLevel,
            octopamineLevel: octopamineLevel,
            membrane: membrane,
            activity: activity,
            presynapticEligibility: presynapticEligibility
        )
    }

    public func restorePersistentState(_ state: FullCNSPersistentState) throws {
        guard state.schemaVersion == FullCNSPersistentState.currentSchemaVersion else {
            throw FullCNSStateError.unsupportedSchema(state.schemaVersion)
        }
        try state.validate(
            graphSHA256: graph.manifest.graphSha256,
            nodeCount: graph.nodeCount
        )
        membrane = state.membrane
        activity = state.activity
        presynapticEligibility = state.presynapticEligibility
        spikeGeneration = Array(repeating: 0, count: graph.nodeCount)
        generation = 0
        globalCursor = state.globalCursor
        cohortCursors = state.cohortCursors.reduce(into: [:]) { result, entry in
            guard let key = UInt32(entry.key) else { return }
            result[key] = entry.value
        }
        homeostaticThreshold = state.homeostaticThreshold
        dopamineLevel = state.dopamineLevel
        serotoninLevel = state.serotoninLevel
        octopamineLevel = state.octopamineLevel
        cumulativeSimulatedSeconds = state.cumulativeSimulatedSeconds
    }

    private func seed(
        _ cohort: [UInt32],
        amplitude rawAmplitude: Double,
        channel: UInt32,
        queue: inout [UInt32]
    ) {
        guard !cohort.isEmpty, rawAmplitude > 0 else { return }
        let amplitude = Float(min(max(rawAmplitude, 0), 1))
        let count = max(1, Int(ceil(
            Double(configuration.maximumSeedsPerCohortPerSubstep) * Double(amplitude)
        )))
        var cursor = cohortCursors[channel, default: 0] % cohort.count
        for _ in 0..<min(count, cohort.count) {
            let index = Int(cohort[cursor])
            guard !silenced[index] else {
                cursor += 1
                if cursor == cohort.count { cursor = 0 }
                continue
            }
            membrane[index] += 0.70 + amplitude * 0.65
            if membrane[index] >= homeostaticThreshold,
               spikeGeneration[index] != generation {
                spikeGeneration[index] = generation
                membrane[index] = 0
                queue.append(UInt32(index))
            }
            cursor += 1
            if cursor == cohort.count { cursor = 0 }
        }
        cohortCursors[channel] = cursor
    }

    private func seedSpontaneousActivity(queue: inout [UInt32]) {
        guard configuration.spontaneousSpikesPerSubstep > 0 else { return }
        let cohort = centralComplexIndices.isEmpty ? sensoryIndices : centralComplexIndices
        guard !cohort.isEmpty else { return }
        for _ in 0..<configuration.spontaneousSpikesPerSubstep {
            let index = Int(cohort[globalCursor % cohort.count])
            globalCursor = (globalCursor + 7_919) % cohort.count
            guard !silenced[index], spikeGeneration[index] != generation else { continue }
            spikeGeneration[index] = generation
            membrane[index] = 0
            queue.append(UInt32(index))
        }
    }

    private func seedStimulatedNeurons(queue: inout [UInt32]) {
        guard stimulationAmplitude > 0 else { return }
        for rawIndex in stimulatedIndices {
            let index = Int(rawIndex)
            guard !silenced[index], spikeGeneration[index] != generation else { continue }
            membrane[index] += 0.75 + stimulationAmplitude * 0.75
            if membrane[index] >= homeostaticThreshold {
                spikeGeneration[index] = generation
                membrane[index] = 0
                queue.append(rawIndex)
            }
        }
    }

    private func effectiveSign(for transmitter: FullCNSNeurotransmitter) -> Float {
        let observedPrediction = transmitter.assumedFastSign
        if observedPrediction != 0 { return observedPrediction }
        switch transmitter {
        case .unclear: return 0.22
        case .dopamine: return 0.06 + dopamineLevel * 0.04
        case .serotonin: return 0.04 + serotoninLevel * 0.03
        case .octopamine: return 0.07 + octopamineLevel * 0.04
        default: return 0
        }
    }

    private func updateModulator(
        for transmitter: FullCNSNeurotransmitter,
        reward: Double,
        punishment: Double
    ) {
        switch transmitter {
        case .dopamine:
            dopamineLevel = min(dopamineLevel + 0.002 + Float(max(reward, punishment)) * 0.004, 1)
        case .serotonin:
            serotoninLevel = min(serotoninLevel + 0.0015, 1)
        case .octopamine:
            octopamineLevel = min(octopamineLevel + 0.0018 + Float(punishment) * 0.003, 1)
        default:
            break
        }
    }

    private func readoutActivity(in indices: [UInt32]) -> Double {
        guard !indices.isEmpty else { return 0 }
        let sum = indices.reduce(Float(0)) {
            let index = Int($1)
            let subthreshold = max(membrane[index], 0) / max(homeostaticThreshold, 0.01)
            return $0 + activity[index] + min(subthreshold, 1) * 0.18
        }
        return Double(sum) / Double(indices.count)
    }

    private func weightedMean(
        _ lhs: Double,
        count lhsCount: Int,
        _ rhs: Double,
        count rhsCount: Int
    ) -> Double {
        let total = lhsCount + rhsCount
        guard total > 0 else { return 0 }
        return (lhs * Double(lhsCount) + rhs * Double(rhsCount)) / Double(total)
    }
}
