import Foundation

/// A falsifiable causal label produced by the engineered self model.
/// It describes the source of a state transition; it is not a claim about
/// subjective experience.
public enum SelfCausalAttribution: String, Codable, CaseIterable, Sendable {
    case selfGenerated
    case external
    case mixed
    case uncertain

    public var displayName: String {
        switch self {
        case .selfGenerated: "自身行动"
        case .external: "外界事件"
        case .mixed: "外因触发 / 自身响应"
        case .uncertain: "暂不确定"
        }
    }
}

public struct FunctionalSelfEpisode: Codable, Equatable, Identifiable, Sendable {
    public var id: UInt64 { tick }

    public let tick: UInt64
    public let recordedAt: Date
    public let behavior: FlyBehavior
    public let actionNeuron: String
    public let attribution: SelfCausalAttribution
    public let predictionError: Double
    public let confidence: Double
    public let summary: String

    public init(
        tick: UInt64,
        recordedAt: Date,
        behavior: FlyBehavior,
        actionNeuron: String,
        attribution: SelfCausalAttribution,
        predictionError: Double,
        confidence: Double,
        summary: String
    ) {
        self.tick = tick
        self.recordedAt = recordedAt
        self.behavior = behavior
        self.actionNeuron = actionNeuron
        self.attribution = attribution
        self.predictionError = Self.clamp(predictionError)
        self.confidence = Self.clamp(confidence)
        self.summary = summary
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// Persisted, inspectable output of the engineered functional self model.
/// Identity continuity, bodily state, agency, uncertainty and autobiographical
/// episodes are deliberately represented as measurable variables.
public struct FunctionalSelfState: Codable, Equatable, Sendable {
    public static let circuitID =
        "ENG-SELF-VISUAL+PROPRIO+VISCERAL+MEMORY→ENG-SELF-PREDICT"
    public static let provenance =
        "engineered/modelled; constrained by MaleCNS sensory, central-complex and descending readouts"
    public static let maximumEpisodeCount = 24

    public let individualID: UUID
    public let identityContinuity: Bool
    public let enabled: Bool
    public let bodilyCoherence: Double
    public let agencyScore: Double
    public let confidence: Double
    public let uncertainty: Double
    public let sensorReliability: Double
    public let actionCapability: Double
    public let visualChannel: Double
    public let proprioceptiveChannel: Double
    public let visceralChannel: Double
    public let memoryChannel: Double
    public let predictionError: Double
    public let causalAttribution: SelfCausalAttribution
    public let predictedDisplacement: Double
    public let observedDisplacement: Double
    public let predictedEnergyDelta: Double
    public let observedEnergyDelta: Double
    public let learnedForwardGain: Double
    public let learnedTurnGain: Double
    public let episodeRevision: UInt64
    public let episodes: [FunctionalSelfEpisode]
    public let explanation: String

    public init(
        individualID: UUID,
        identityContinuity: Bool = true,
        enabled: Bool = true,
        bodilyCoherence: Double,
        agencyScore: Double,
        confidence: Double,
        uncertainty: Double? = nil,
        sensorReliability: Double,
        actionCapability: Double,
        visualChannel: Double = 0,
        proprioceptiveChannel: Double = 0,
        visceralChannel: Double = 0,
        memoryChannel: Double = 0,
        predictionError: Double,
        causalAttribution: SelfCausalAttribution,
        predictedDisplacement: Double,
        observedDisplacement: Double,
        predictedEnergyDelta: Double,
        observedEnergyDelta: Double,
        learnedForwardGain: Double = 1,
        learnedTurnGain: Double = 1,
        episodeRevision: UInt64 = 0,
        episodes: [FunctionalSelfEpisode] = [],
        explanation: String
    ) {
        self.individualID = individualID
        self.identityContinuity = identityContinuity
        self.enabled = enabled
        self.bodilyCoherence = Self.clamp(bodilyCoherence)
        self.agencyScore = Self.clamp(agencyScore)
        self.confidence = Self.clamp(confidence)
        self.uncertainty = Self.clamp(uncertainty ?? (1 - confidence))
        self.sensorReliability = Self.clamp(sensorReliability)
        self.actionCapability = Self.clamp(actionCapability)
        self.visualChannel = Self.clamp(visualChannel)
        self.proprioceptiveChannel = Self.clamp(proprioceptiveChannel)
        self.visceralChannel = Self.clamp(visceralChannel)
        self.memoryChannel = Self.clamp(memoryChannel)
        self.predictionError = Self.clamp(predictionError)
        self.causalAttribution = causalAttribution
        self.predictedDisplacement = max(predictedDisplacement, 0)
        self.observedDisplacement = max(observedDisplacement, 0)
        self.predictedEnergyDelta = predictedEnergyDelta
        self.observedEnergyDelta = observedEnergyDelta
        self.learnedForwardGain = min(max(learnedForwardGain, 0), 2)
        self.learnedTurnGain = min(max(learnedTurnGain, -2), 2)
        self.episodeRevision = episodeRevision
        self.episodes = Array(episodes.suffix(Self.maximumEpisodeCount))
        self.explanation = explanation
    }

    public static func initial(
        individualID: UUID,
        enabled: Bool = true
    ) -> FunctionalSelfState {
        FunctionalSelfState(
            individualID: individualID,
            enabled: enabled,
            bodilyCoherence: enabled ? 0.62 : 0,
            agencyScore: enabled ? 0.5 : 0,
            confidence: enabled ? 0.55 : 0,
            sensorReliability: 1,
            actionCapability: 0.72,
            predictionError: 0,
            causalAttribution: .uncertain,
            predictedDisplacement: 0,
            observedDisplacement: 0,
            predictedEnergyDelta: 0,
            observedEnergyDelta: 0,
            explanation: enabled
                ? "正在建立身体连续性与行动后果基线"
                : "功能性自我模型已停用，保留此状态用于消融对照"
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - v1.3 Counterfactual self and calibrated metacognition

public struct CounterfactualActionEvaluation: Codable, Equatable, Identifiable, Sendable {
    public var id: FlyBehavior { behavior }

    public let behavior: FlyBehavior
    public let actionNeuron: String
    public let predictedDisplacement: Double
    public let predictedEnergyCost: Double
    public let predictedThreatExposure: Double
    public let expectedInformationGain: Double
    public let expectedUtility: Double
    public let confidence: Double

    public init(
        behavior: FlyBehavior,
        actionNeuron: String,
        predictedDisplacement: Double,
        predictedEnergyCost: Double,
        predictedThreatExposure: Double,
        expectedInformationGain: Double,
        expectedUtility: Double,
        confidence: Double
    ) {
        self.behavior = behavior
        self.actionNeuron = actionNeuron
        self.predictedDisplacement = max(predictedDisplacement, 0)
        self.predictedEnergyCost = max(predictedEnergyCost, 0)
        self.predictedThreatExposure = Self.clamp(predictedThreatExposure)
        self.expectedInformationGain = Self.clamp(expectedInformationGain)
        self.expectedUtility = min(max(expectedUtility, -1), 1)
        self.confidence = Self.clamp(confidence)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// Inspectable output of the v1.3 counterfactual and metacognitive layer.
/// Candidate futures and calibration metrics are engineered quantities.
public struct CounterfactualSelfState: Codable, Equatable, Sendable {
    public static let circuitID =
        "ENG-SELF-PREDICT↔ENG-COUNTERFACTUAL-ROLLOUT→ENG-METACOGNITION"
    public static let provenance =
        "engineered/modelled; constrained by embodied state and MaleCNS-derived readouts"

    public let individualID: UUID
    public let identityContinuity: Bool
    public let enabled: Bool
    public let revision: UInt64
    public let horizonSeconds: Double
    public let candidates: [CounterfactualActionEvaluation]
    public let selectedBehavior: FlyBehavior
    public let selectedActionNeuron: String
    public let selfHypothesisProbability: Double
    public let worldHypothesisProbability: Double
    public let ambiguity: Double
    public let epistemicDrive: Double
    public let shouldProbe: Bool
    public let calibrationSampleCount: Int
    public let calibrationAccuracy: Double
    public let meanDecisionConfidence: Double
    public let brierScore: Double
    public let calibrationError: Double
    public let blindExternalEventCount: Int
    public let explanation: String

    public init(
        individualID: UUID,
        identityContinuity: Bool = true,
        enabled: Bool = true,
        revision: UInt64 = 0,
        horizonSeconds: Double = 1.2,
        candidates: [CounterfactualActionEvaluation] = [],
        selectedBehavior: FlyBehavior = .exploring,
        selectedActionNeuron: String = "ENG-ACT-EXPLORE",
        selfHypothesisProbability: Double = 0.5,
        worldHypothesisProbability: Double = 0.5,
        ambiguity: Double = 1,
        epistemicDrive: Double = 0.5,
        shouldProbe: Bool = true,
        calibrationSampleCount: Int = 0,
        calibrationAccuracy: Double = 0,
        meanDecisionConfidence: Double = 0,
        brierScore: Double = 0,
        calibrationError: Double = 1,
        blindExternalEventCount: Int = 0,
        explanation: String = "正在建立反事实行动与因果假设基线"
    ) {
        self.individualID = individualID
        self.identityContinuity = identityContinuity
        self.enabled = enabled
        self.revision = revision
        self.horizonSeconds = min(max(horizonSeconds, 0.1), 5)
        self.candidates = candidates
        self.selectedBehavior = selectedBehavior
        self.selectedActionNeuron = selectedActionNeuron
        self.selfHypothesisProbability = Self.clamp(selfHypothesisProbability)
        self.worldHypothesisProbability = Self.clamp(worldHypothesisProbability)
        self.ambiguity = Self.clamp(ambiguity)
        self.epistemicDrive = Self.clamp(epistemicDrive)
        self.shouldProbe = shouldProbe
        self.calibrationSampleCount = max(calibrationSampleCount, 0)
        self.calibrationAccuracy = Self.clamp(calibrationAccuracy)
        self.meanDecisionConfidence = Self.clamp(meanDecisionConfidence)
        self.brierScore = Self.clamp(brierScore)
        self.calibrationError = Self.clamp(calibrationError)
        self.blindExternalEventCount = max(blindExternalEventCount, 0)
        self.explanation = explanation
    }

    public static func initial(
        individualID: UUID,
        enabled: Bool = true
    ) -> CounterfactualSelfState {
        CounterfactualSelfState(
            individualID: individualID,
            enabled: enabled,
            shouldProbe: enabled,
            explanation: enabled
                ? "正在建立反事实行动与因果假设基线"
                : "反事实自我模型已停用，用于消融对照"
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - v1.4 Long-term goals, preferences and semantic self

public enum LongTermSelfGoal: String, Codable, CaseIterable, Sendable {
    case maintainEnergy
    case avoidThreat
    case exploreWorld
    case restoreBody
    case reduceUncertainty
    case observeOther

    public var displayName: String {
        switch self {
        case .maintainEnergy: "维持能量"
        case .avoidThreat: "保持安全"
        case .exploreWorld: "探索环境"
        case .restoreBody: "恢复身体"
        case .reduceUncertainty: "消除不确定"
        case .observeOther: "观察他者"
        }
    }
}

public struct SelfPreferenceProfile: Codable, Equatable, Sendable {
    public let exploration: Double
    public let caution: Double
    public let energyConservation: Double
    public let cleanliness: Double
    public let socialInterest: Double

    public init(
        exploration: Double = 0.62,
        caution: Double = 0.42,
        energyConservation: Double = 0.48,
        cleanliness: Double = 0.50,
        socialInterest: Double = 0.45
    ) {
        self.exploration = Self.clamp(exploration)
        self.caution = Self.clamp(caution)
        self.energyConservation = Self.clamp(energyConservation)
        self.cleanliness = Self.clamp(cleanliness)
        self.socialInterest = Self.clamp(socialInterest)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct SemanticSelfBelief: Codable, Equatable, Identifiable, Sendable {
    public var id: String { key }

    public let key: String
    public let displayName: String
    public let value: Double
    public let confidence: Double
    public let evidenceCount: Int
    public let summary: String

    public init(
        key: String,
        displayName: String,
        value: Double,
        confidence: Double,
        evidenceCount: Int,
        summary: String
    ) {
        self.key = key
        self.displayName = displayName
        self.value = min(max(value, -1), 1)
        self.confidence = Self.clamp(confidence)
        self.evidenceCount = max(evidenceCount, 0)
        self.summary = summary
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct SemanticSelfState: Codable, Equatable, Sendable {
    public static let circuitID =
        "ENG-EPISODE-CONSOLIDATE→ENG-SEMANTIC-SELF↔ENG-LONG-GOAL"
    public static let provenance =
        "engineered/modelled; learned from the individual runtime history"

    public let individualID: UUID
    public let identityContinuity: Bool
    public let enabled: Bool
    public let revision: UInt64
    public let activeGoal: LongTermSelfGoal
    public let goalSinceTick: UInt64
    public let goalStability: Double
    public let preferences: SelfPreferenceProfile
    public let beliefs: [SemanticSelfBelief]
    public let consolidationCount: Int
    public let narrativeSummary: String

    public init(
        individualID: UUID,
        identityContinuity: Bool = true,
        enabled: Bool = true,
        revision: UInt64 = 0,
        activeGoal: LongTermSelfGoal = .exploreWorld,
        goalSinceTick: UInt64 = 0,
        goalStability: Double = 0,
        preferences: SelfPreferenceProfile = SelfPreferenceProfile(),
        beliefs: [SemanticSelfBelief] = [],
        consolidationCount: Int = 0,
        narrativeSummary: String = "正在把经历整合为长期身体知识"
    ) {
        self.individualID = individualID
        self.identityContinuity = identityContinuity
        self.enabled = enabled
        self.revision = revision
        self.activeGoal = activeGoal
        self.goalSinceTick = goalSinceTick
        self.goalStability = Self.clamp(goalStability)
        self.preferences = preferences
        self.beliefs = beliefs
        self.consolidationCount = max(consolidationCount, 0)
        self.narrativeSummary = narrativeSummary
    }

    public static func initial(
        individualID: UUID,
        enabled: Bool = true
    ) -> SemanticSelfState {
        SemanticSelfState(
            individualID: individualID,
            enabled: enabled,
            narrativeSummary: enabled
                ? "正在把经历整合为长期身体知识"
                : "语义自我与长期目标已停用，用于消融对照"
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - v1.5 Self/other distinction and other-agent model

public enum SelfOtherAttribution: String, Codable, CaseIterable, Sendable {
    case selfAgent
    case otherAgent
    case environment
    case joint
    case uncertain

    public var displayName: String {
        switch self {
        case .selfAgent: "自身"
        case .otherAgent: "他者"
        case .environment: "环境"
        case .joint: "共同作用"
        case .uncertain: "暂不确定"
        }
    }
}

public struct SocialSelfState: Codable, Equatable, Sendable {
    public static let circuitID =
        "ENG-SELF-MODEL↔ENG-OTHER-MODEL→ENG-SELF-OTHER-GATE"
    public static let provenance =
        "engineered/modelled; social evidence is synthetic unless explicitly sourced"

    public let individualID: UUID
    public let identityContinuity: Bool
    public let enabled: Bool
    public let revision: UInt64
    public let otherPresent: Bool
    public let trackedOtherID: String?
    public let selfOtherSeparation: Double
    public let otherAgencyProbability: Double
    public let predictedOtherResponse: Double
    public let observedOtherMotion: Double
    public let affiliation: Double
    public let vigilance: Double
    public let jointActionProbability: Double
    public let attribution: SelfOtherAttribution
    public let socialEpisodeCount: Int
    public let explanation: String

    public init(
        individualID: UUID,
        identityContinuity: Bool = true,
        enabled: Bool = true,
        revision: UInt64 = 0,
        otherPresent: Bool = false,
        trackedOtherID: String? = nil,
        selfOtherSeparation: Double = 0.5,
        otherAgencyProbability: Double = 0,
        predictedOtherResponse: Double = 0,
        observedOtherMotion: Double = 0,
        affiliation: Double = 0.5,
        vigilance: Double = 0,
        jointActionProbability: Double = 0,
        attribution: SelfOtherAttribution = .uncertain,
        socialEpisodeCount: Int = 0,
        explanation: String = "尚未观察到可归因的他者行为"
    ) {
        self.individualID = individualID
        self.identityContinuity = identityContinuity
        self.enabled = enabled
        self.revision = revision
        self.otherPresent = otherPresent
        self.trackedOtherID = trackedOtherID
        self.selfOtherSeparation = Self.clamp(selfOtherSeparation)
        self.otherAgencyProbability = Self.clamp(otherAgencyProbability)
        self.predictedOtherResponse = Self.clamp(predictedOtherResponse)
        self.observedOtherMotion = Self.clamp(observedOtherMotion)
        self.affiliation = Self.clamp(affiliation)
        self.vigilance = Self.clamp(vigilance)
        self.jointActionProbability = Self.clamp(jointActionProbability)
        self.attribution = attribution
        self.socialEpisodeCount = max(socialEpisodeCount, 0)
        self.explanation = explanation
    }

    public static func initial(
        individualID: UUID,
        enabled: Bool = true
    ) -> SocialSelfState {
        SocialSelfState(
            individualID: individualID,
            enabled: enabled,
            selfOtherSeparation: enabled ? 0.5 : 0,
            affiliation: enabled ? 0.5 : 0,
            explanation: enabled
                ? "尚未观察到可归因的他者行为"
                : "他者模型已停用，用于消融对照"
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
