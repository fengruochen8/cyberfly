import Foundation

public struct FullCNSNeuronQuery: Equatable, Sendable {
    public var bodyIDText: String
    public var role: FullCNSNodeRole?
    public var transmitter: FullCNSNeurotransmitter?
    public var hemisphere: FullCNSHemisphere?
    public var limit: Int

    public init(
        bodyIDText: String = "",
        role: FullCNSNodeRole? = nil,
        transmitter: FullCNSNeurotransmitter? = nil,
        hemisphere: FullCNSHemisphere? = nil,
        limit: Int = 120
    ) {
        self.bodyIDText = bodyIDText
        self.role = role
        self.transmitter = transmitter
        self.hemisphere = hemisphere
        self.limit = min(max(limit, 1), 500)
    }
}

public struct FullCNSNeuronObservation: Equatable, Sendable, Identifiable {
    public var id: UInt64 { bodyID }

    public let nodeIndex: Int
    public let bodyID: UInt64
    public let annotationType: String?
    public let annotationInstance: String?
    public let roles: FullCNSNodeRole
    public let transmitter: FullCNSNeurotransmitter
    public let hemisphere: FullCNSHemisphere
    public let traceQuality: UInt8
    public let somaX: Int32?
    public let somaY: Int32?
    public let somaZ: Int32?
    public let transmitterConfidence: Double
    public let outgoingEdgeCount: Int
    public let incomingEdgeCount: Int
    public let membranePotential: Double
    public let activity: Double
    public let presynapticEligibility: Double
    public let isSilenced: Bool
    public let isStimulated: Bool
}

public enum FullCNSInterventionMode: String, Codable, CaseIterable, Sendable {
    case silence
    case stimulate
}

public enum FullCNSExperimentExpectation: String, Codable, Sendable {
    case observeDifference
    case eliminateVisualTurnBias
}

public struct FullCNSExperimentDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let targetBodyIDs: [UInt64]
    public let intervention: FullCNSInterventionMode
    public let stimulationAmplitude: Double
    public let input: FullCNSSensoryInput
    public let duration: Double
    public let sampleInterval: Double
    public let expectation: FullCNSExperimentExpectation

    public init(
        name: String,
        targetBodyIDs: [UInt64],
        intervention: FullCNSInterventionMode,
        stimulationAmplitude: Double = 1,
        input: FullCNSSensoryInput,
        duration: Double = 0.8,
        sampleInterval: Double = 0.1,
        expectation: FullCNSExperimentExpectation = .observeDifference
    ) {
        self.name = name
        self.targetBodyIDs = Array(Set(targetBodyIDs)).sorted()
        self.intervention = intervention
        self.stimulationAmplitude = min(max(stimulationAmplitude, 0), 1)
        self.input = input
        self.duration = min(max(duration, 0.1), 10)
        self.sampleInterval = min(max(sampleInterval, 0.01), 0.5)
        self.expectation = expectation
    }

    public static let dng13VisualSteering = FullCNSExperimentDefinition(
        name: "DNg13 视觉转向",
        targetBodyIDs: [11_074, 512_006],
        intervention: .silence,
        input: FullCNSSensoryInput(
            leftVisualMotion: 1,
            rightVisualMotion: 0.05,
            touch: 0.2
        ),
        duration: 0.8,
        sampleInterval: 0.1,
        expectation: .eliminateVisualTurnBias
    )
}

public struct FullCNSExperimentSample: Codable, Equatable, Sendable, Identifiable {
    public var id: Double { simulatedSeconds }

    public let simulatedSeconds: Double
    public let controlTurnBias: Double
    public let interventionTurnBias: Double
    public let controlActiveNeuronCount: Int
    public let interventionActiveNeuronCount: Int
    public let controlDescendingActivity: Double
    public let interventionDescendingActivity: Double
    public let controlMotorActivity: Double
    public let interventionMotorActivity: Double
    public let controlDopamineLevel: Double
    public let interventionDopamineLevel: Double
    public let controlEdgeEventCount: Int
    public let interventionEdgeEventCount: Int
}

public struct FullCNSExperimentResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let createdAt: Date
    public let dataset: String
    public let graphSHA256: String
    public let definition: FullCNSExperimentDefinition
    public let resolvedTargetCount: Int
    public let samples: [FullCNSExperimentSample]
    public let controlPeakAbsoluteTurnBias: Double
    public let interventionPeakAbsoluteTurnBias: Double
    public let turnBiasReductionFraction: Double
    public let controlMeanActiveNeuronCount: Double
    public let interventionMeanActiveNeuronCount: Double
    public let controlTotalEdgeEvents: Int
    public let interventionTotalEdgeEvents: Int
    public let eventBudgetSaturated: Bool
    public let expectationPassed: Bool?

    public var summary: String {
        if definition.expectation == .eliminateVisualTurnBias {
            if expectationPassed == true {
                return "静默目标后视觉转向读出归零，且其余全图传播仍在继续。"
            }
            return "本次结果未达到 DNg13 视觉转向因果门槛。"
        }
        let percent = Int((turnBiasReductionFraction * 100).rounded())
        return "干预后的峰值转向偏置相对对照变化约 \(percent)%。"
    }
}

public enum FullCNSExperimentError: Error, LocalizedError {
    case noResolvedTargets

    public var errorDescription: String? {
        switch self {
        case .noResolvedTargets:
            "没有任何输入 body ID 能在当前 MaleCNS 图中找到"
        }
    }
}

public enum FullCNSExperimentRunner {
    public static func run(
        graph: FullCNSGraph,
        definition: FullCNSExperimentDefinition,
        now: Date = Date()
    ) throws -> FullCNSExperimentResult {
        let control = FullCNSRuntime(graph: graph)
        let intervention = FullCNSRuntime(graph: graph)
        let resolvedTargetCount: Int
        switch definition.intervention {
        case .silence:
            resolvedTargetCount = intervention.setSilenced(bodyIDs: definition.targetBodyIDs)
        case .stimulate:
            resolvedTargetCount = intervention.setStimulated(
                bodyIDs: definition.targetBodyIDs,
                amplitude: definition.stimulationAmplitude
            )
        }
        guard resolvedTargetCount > 0 else {
            throw FullCNSExperimentError.noResolvedTargets
        }

        let stepCount = max(1, Int(ceil(definition.duration / definition.sampleInterval)))
        var samples: [FullCNSExperimentSample] = []
        samples.reserveCapacity(stepCount)
        var controlPeak = 0.0
        var interventionPeak = 0.0
        var controlActiveTotal = 0
        var interventionActiveTotal = 0
        var controlEdgeTotal = 0
        var interventionEdgeTotal = 0
        var saturated = false

        for step in 1...stepCount {
            let controlMetrics = control.step(
                deltaTime: definition.sampleInterval,
                input: definition.input
            )
            let interventionMetrics = intervention.step(
                deltaTime: definition.sampleInterval,
                input: definition.input
            )
            controlPeak = max(controlPeak, abs(controlMetrics.turnBias))
            interventionPeak = max(interventionPeak, abs(interventionMetrics.turnBias))
            controlActiveTotal += controlMetrics.activeNeuronCount
            interventionActiveTotal += interventionMetrics.activeNeuronCount
            controlEdgeTotal += controlMetrics.edgeEventCount
            interventionEdgeTotal += interventionMetrics.edgeEventCount
            saturated = saturated
                || controlMetrics.eventBudgetSaturated
                || interventionMetrics.eventBudgetSaturated
            samples.append(FullCNSExperimentSample(
                simulatedSeconds: Double(step) * definition.sampleInterval,
                controlTurnBias: controlMetrics.turnBias,
                interventionTurnBias: interventionMetrics.turnBias,
                controlActiveNeuronCount: controlMetrics.activeNeuronCount,
                interventionActiveNeuronCount: interventionMetrics.activeNeuronCount,
                controlDescendingActivity: controlMetrics.descendingActivity,
                interventionDescendingActivity: interventionMetrics.descendingActivity,
                controlMotorActivity: controlMetrics.motorActivity,
                interventionMotorActivity: interventionMetrics.motorActivity,
                controlDopamineLevel: controlMetrics.dopamineLevel,
                interventionDopamineLevel: interventionMetrics.dopamineLevel,
                controlEdgeEventCount: controlMetrics.edgeEventCount,
                interventionEdgeEventCount: interventionMetrics.edgeEventCount
            ))
        }

        let reduction = controlPeak > 0
            ? min(max(1 - interventionPeak / controlPeak, -1), 1)
            : 0
        let expectationPassed: Bool?
        switch definition.expectation {
        case .observeDifference:
            expectationPassed = nil
        case .eliminateVisualTurnBias:
            expectationPassed = resolvedTargetCount == definition.targetBodyIDs.count
                && controlPeak > 0.02
                && interventionPeak < 0.000_001
                && interventionEdgeTotal > 0
        }

        return FullCNSExperimentResult(
            schemaVersion: 1,
            createdAt: now,
            dataset: graph.manifest.dataset,
            graphSHA256: graph.manifest.graphSha256,
            definition: definition,
            resolvedTargetCount: resolvedTargetCount,
            samples: samples,
            controlPeakAbsoluteTurnBias: controlPeak,
            interventionPeakAbsoluteTurnBias: interventionPeak,
            turnBiasReductionFraction: reduction,
            controlMeanActiveNeuronCount: Double(controlActiveTotal) / Double(stepCount),
            interventionMeanActiveNeuronCount: Double(interventionActiveTotal) / Double(stepCount),
            controlTotalEdgeEvents: controlEdgeTotal,
            interventionTotalEdgeEvents: interventionEdgeTotal,
            eventBudgetSaturated: saturated,
            expectationPassed: expectationPassed
        )
    }
}
