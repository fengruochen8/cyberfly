import CyberFlyCore
import Foundation

public struct SelfBodyObservation: Equatable, Sendable {
    public let positionX: Double
    public let positionY: Double
    public let headingRadians: Double
    public let energy: Double
    public let fatigue: Double
    public let groomingNeed: Double
    public let lifeState: FlyLifeState

    public init(
        positionX: Double,
        positionY: Double,
        headingRadians: Double,
        energy: Double,
        fatigue: Double,
        groomingNeed: Double,
        lifeState: FlyLifeState
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.headingRadians = headingRadians
        self.energy = min(max(energy, 0), 1)
        self.fatigue = min(max(fatigue, 0), 1)
        self.groomingNeed = min(max(groomingNeed, 0), 1)
        self.lifeState = lifeState
    }
}

public struct SelfActionCommand: Equatable, Sendable {
    public let behavior: FlyBehavior
    public let actionNeuron: String
    public let actionConfidence: Double
    public let forwardSpeed: Double
    public let turnRateRadiansPerSecond: Double
    public let wingDrive: Double
    public let feedingDrive: Double
    public let groomingDrive: Double
    public let restDrive: Double

    public init(
        behavior: FlyBehavior,
        actionNeuron: String,
        actionConfidence: Double,
        forwardSpeed: Double,
        turnRateRadiansPerSecond: Double,
        wingDrive: Double,
        feedingDrive: Double,
        groomingDrive: Double,
        restDrive: Double
    ) {
        self.behavior = behavior
        self.actionNeuron = actionNeuron
        self.actionConfidence = Self.clamp(actionConfidence)
        self.forwardSpeed = max(forwardSpeed, 0)
        self.turnRateRadiansPerSecond = turnRateRadiansPerSecond
        self.wingDrive = Self.clamp(wingDrive)
        self.feedingDrive = Self.clamp(feedingDrive)
        self.groomingDrive = Self.clamp(groomingDrive)
        self.restDrive = Self.clamp(restDrive)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct SelfExternalEvidence: Equatable, Sendable {
    public let touch: Double
    public let threat: Double
    public let contamination: Double
    public let sensorReliability: Double
    public let visualMotion: Double
    public let memoryConfidence: Double
    public let displacementX: Double
    public let displacementY: Double
    public let headingDelta: Double

    public init(
        touch: Double = 0,
        threat: Double = 0,
        contamination: Double = 0,
        sensorReliability: Double = 1,
        visualMotion: Double = 0,
        memoryConfidence: Double = 0,
        displacementX: Double = 0,
        displacementY: Double = 0,
        headingDelta: Double = 0
    ) {
        self.touch = Self.clamp(touch)
        self.threat = Self.clamp(threat)
        self.contamination = Self.clamp(contamination)
        self.sensorReliability = Self.clamp(sensorReliability)
        self.visualMotion = Self.clamp(visualMotion)
        self.memoryConfidence = Self.clamp(memoryConfidence)
        self.displacementX = displacementX
        self.displacementY = displacementY
        self.headingDelta = headingDelta
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct SelfActionPrediction: Equatable, Sendable {
    public let deltaX: Double
    public let deltaY: Double
    public let headingDelta: Double
    public let energyDelta: Double
    public let fatigueDelta: Double
    public let groomingDelta: Double
    public let nominalDisplacement: Double
    public let nominalHeadingDelta: Double

    public var displacement: Double { hypot(deltaX, deltaY) }
}

/// Engineering implementation of a minimal functional self model.
///
/// It combines distributed body channels, an efference-copy prediction and
/// next-state comparison. Its output can be ablated and tested. Nothing here
/// is labelled as an observed MaleCNS neuron or as evidence of consciousness.
public struct FunctionalSelfModel: Sendable {
    public static let circuitID = FunctionalSelfState.circuitID
    public static let provenance = FunctionalSelfState.provenance

    public let individualID: UUID
    public let isEnabled: Bool

    private var confidence: Double
    private var agencyScore: Double
    private var bodilyCoherence: Double
    private var learnedForwardGain: Double
    private var learnedTurnGain: Double
    private var episodes: [FunctionalSelfEpisode]
    private var episodeRevision: UInt64
    private var lastRecordedBehavior: FlyBehavior?
    private var lastAttribution: SelfCausalAttribution = .uncertain
    private var lastExternalTrigger = 0.0
    private var latestState: FunctionalSelfState

    public init(
        individualID: UUID,
        enabled: Bool = true,
        restoring state: FunctionalSelfState? = nil
    ) {
        self.individualID = individualID
        self.isEnabled = enabled
        if enabled, let state, state.individualID == individualID, state.enabled {
            confidence = state.confidence
            agencyScore = state.agencyScore
            bodilyCoherence = state.bodilyCoherence
            learnedForwardGain = state.learnedForwardGain
            learnedTurnGain = state.learnedTurnGain
            episodes = Self.compactedEpisodes(state.episodes)
            episodeRevision = state.episodeRevision
            lastRecordedBehavior = state.episodes.last?.behavior
            lastAttribution = state.causalAttribution
            latestState = state
        } else {
            confidence = enabled ? 0.55 : 0
            agencyScore = enabled ? 0.5 : 0
            bodilyCoherence = enabled ? 0.62 : 0
            learnedForwardGain = 1
            learnedTurnGain = 1
            episodes = []
            episodeRevision = 0
            lastRecordedBehavior = nil
            latestState = FunctionalSelfState.initial(
                individualID: individualID,
                enabled: enabled
            )
        }
    }

    public var state: FunctionalSelfState { latestState }

    public func predict(
        action: SelfActionCommand,
        body: SelfBodyObservation,
        deltaTime rawDeltaTime: TimeInterval,
        expectedEnergyDelta: Double,
        expectedFatigueDelta: Double,
        expectedGroomingDelta: Double
    ) -> SelfActionPrediction {
        guard isEnabled else {
            return SelfActionPrediction(
                deltaX: 0,
                deltaY: 0,
                headingDelta: 0,
                energyDelta: 0,
                fatigueDelta: 0,
                groomingDelta: 0,
                nominalDisplacement: 0,
                nominalHeadingDelta: 0
            )
        }
        let deltaTime = min(max(rawDeltaTime, 0.001), 1)
        let headingDelta = action.turnRateRadiansPerSecond * deltaTime * learnedTurnGain
        let distance = action.forwardSpeed * deltaTime * learnedForwardGain
        let predictedHeading = body.headingRadians + headingDelta
        return SelfActionPrediction(
            deltaX: cos(predictedHeading) * distance,
            deltaY: sin(predictedHeading) * distance,
            headingDelta: headingDelta,
            energyDelta: expectedEnergyDelta,
            fatigueDelta: expectedFatigueDelta,
            groomingDelta: expectedGroomingDelta,
            nominalDisplacement: action.forwardSpeed * deltaTime,
            nominalHeadingDelta: action.turnRateRadiansPerSecond * deltaTime
        )
    }

    @discardableResult
    public mutating func observe(
        prediction: SelfActionPrediction,
        before: SelfBodyObservation,
        after: SelfBodyObservation,
        action: SelfActionCommand,
        external: SelfExternalEvidence = SelfExternalEvidence(),
        tick: UInt64,
        now: Date
    ) -> FunctionalSelfState {
        guard isEnabled else {
            latestState = FunctionalSelfState.initial(
                individualID: individualID,
                enabled: false
            )
            return latestState
        }

        let actualDX = after.positionX - before.positionX
        let actualDY = after.positionY - before.positionY
        let actualHeadingDelta = Self.normalizedAngle(
            after.headingRadians - before.headingRadians
        )
        let selfDX = actualDX - external.displacementX
        let selfDY = actualDY - external.displacementY
        let selfHeadingDelta = Self.normalizedAngle(
            actualHeadingDelta - external.headingDelta
        )
        let actualEnergyDelta = after.energy - before.energy
        let actualFatigueDelta = after.fatigue - before.fatigue
        let actualGroomingDelta = after.groomingNeed - before.groomingNeed

        let positionResidual = hypot(
            actualDX - prediction.deltaX,
            actualDY - prediction.deltaY
        )
        let positionScale = max(prediction.displacement + 0.006, 0.008)
        let positionError = Self.clamp(positionResidual / positionScale)
        let headingError = Self.clamp(
            abs(Self.normalizedAngle(actualHeadingDelta - prediction.headingDelta)) / 0.45
        )
        let energyError = Self.clamp(
            abs(actualEnergyDelta - prediction.energyDelta) / 0.025
        )
        let fatigueError = Self.clamp(
            abs(actualFatigueDelta - prediction.fatigueDelta) / 0.025
        )
        let groomingError = Self.clamp(
            abs(actualGroomingDelta - prediction.groomingDelta) / 0.035
        )
        let predictionError = Self.clamp(
            positionError * 0.42
                + headingError * 0.22
                + energyError * 0.16
                + fatigueError * 0.10
                + groomingError * 0.10
        )

        let explicitDisplacement = hypot(external.displacementX, external.displacementY)
            + abs(external.headingDelta) * 0.08
        let externalTrigger = max(external.touch, external.threat, external.contamination * 0.65)
        let motorStrength = Self.clamp(
            action.forwardSpeed / 0.13
                + abs(action.turnRateRadiansPerSecond) / 4 * 0.35
                + action.wingDrive * 0.45
                + action.feedingDrive * 0.25
                + action.groomingDrive * 0.25
        )

        let attribution: SelfCausalAttribution
        if explicitDisplacement > 0.008 {
            attribution = .external
        } else if externalTrigger > 0.55 {
            attribution = motorStrength > 0.08 ? .mixed : .external
        } else if motorStrength > 0.05, predictionError < 0.48 {
            attribution = .selfGenerated
        } else if predictionError > 0.56 {
            attribution = .external
        } else {
            attribution = .uncertain
        }

        let agencyTarget: Double
        switch attribution {
        case .selfGenerated: agencyTarget = 0.94 - predictionError * 0.35
        case .mixed: agencyTarget = 0.48 - predictionError * 0.12
        case .external: agencyTarget = 0.08
        case .uncertain: agencyTarget = 0.42 - predictionError * 0.15
        }
        agencyScore = Self.approach(agencyScore, agencyTarget, rate: 0.42)

        let continuity = before.lifeState == after.lifeState ? 1.0 : 0.72
        let coherenceTarget = Self.clamp(
            continuity * 0.22
                + (1 - predictionError) * 0.58
                + external.sensorReliability * 0.20
        )
        bodilyCoherence = Self.approach(bodilyCoherence, coherenceTarget, rate: 0.34)
        let confidenceTarget = external.sensorReliability
            * Self.clamp(1 - predictionError * 0.78)
            * (0.62 + bodilyCoherence * 0.38)
        confidence = Self.approach(confidence, confidenceTarget, rate: 0.32)

        updateControlCalibration(
            action: action,
            before: before,
            prediction: prediction,
            selfDX: selfDX,
            selfDY: selfDY,
            selfHeadingDelta: selfHeadingDelta,
            external: external
        )

        let capability = Self.clamp(
            after.energy * 0.52
                + (1 - after.fatigue) * 0.28
                + (after.lifeState == .active ? 0.20 : 0)
        )
        let proprioceptiveChannel = Self.clamp(
            hypot(actualDX, actualDY) / 0.013 + abs(actualHeadingDelta) / 0.45
        )
        let visceralChannel = Self.clamp(
            (1 - after.energy) * 0.45
                + after.fatigue * 0.30
                + after.groomingNeed * 0.25
        )
        let summary = Self.summary(
            attribution: attribution,
            behavior: action.behavior,
            predictionError: predictionError,
            sensorReliability: external.sensorReliability
        )
        let lastEpisodeTick = episodes.last?.tick ?? 0
        let attributionChanged = attribution != lastAttribution
        let externalTriggerStarted = externalTrigger > 0.55
            && lastExternalTrigger <= 0.55
        let sensorBoundaryCrossed = (external.sensorReliability < 0.45)
            != (latestState.sensorReliability < 0.45)
        let shouldRecord = episodes.isEmpty
            || explicitDisplacement > 0.008
            || sensorBoundaryCrossed
            || (externalTriggerStarted && tick > lastEpisodeTick + 5)
            || (attributionChanged && tick > lastEpisodeTick + 10)
            || ((attribution == .external || attribution == .mixed)
                && tick > lastEpisodeTick + 20)
            || (predictionError > 0.35 && tick > lastEpisodeTick + 10)
            || (action.behavior != lastRecordedBehavior && tick > lastEpisodeTick + 10)
        if shouldRecord, episodes.last?.tick != tick {
            episodeRevision &+= 1
            episodes.append(FunctionalSelfEpisode(
                tick: tick,
                recordedAt: now,
                behavior: action.behavior,
                actionNeuron: action.actionNeuron,
                attribution: attribution,
                predictionError: predictionError,
                confidence: confidence,
                summary: summary
            ))
            if episodes.count > FunctionalSelfState.maximumEpisodeCount {
                episodes.removeFirst(episodes.count - FunctionalSelfState.maximumEpisodeCount)
            }
            lastRecordedBehavior = action.behavior
        }
        lastAttribution = attribution
        lastExternalTrigger = externalTrigger

        latestState = FunctionalSelfState(
            individualID: individualID,
            identityContinuity: true,
            enabled: true,
            bodilyCoherence: bodilyCoherence,
            agencyScore: agencyScore,
            confidence: confidence,
            sensorReliability: external.sensorReliability,
            actionCapability: capability,
            visualChannel: external.visualMotion,
            proprioceptiveChannel: proprioceptiveChannel,
            visceralChannel: visceralChannel,
            memoryChannel: external.memoryConfidence,
            predictionError: predictionError,
            causalAttribution: attribution,
            predictedDisplacement: prediction.displacement,
            observedDisplacement: hypot(actualDX, actualDY),
            predictedEnergyDelta: prediction.energyDelta,
            observedEnergyDelta: actualEnergyDelta,
            learnedForwardGain: learnedForwardGain,
            learnedTurnGain: learnedTurnGain,
            episodeRevision: episodeRevision,
            episodes: episodes,
            explanation: summary
        )
        return latestState
    }

    private mutating func updateControlCalibration(
        action: SelfActionCommand,
        before: SelfBodyObservation,
        prediction: SelfActionPrediction,
        selfDX: Double,
        selfDY: Double,
        selfHeadingDelta: Double,
        external: SelfExternalEvidence
    ) {
        guard external.sensorReliability >= 0.45,
              max(external.touch, external.threat) < 0.55 else { return }

        if action.forwardSpeed > 0.008 {
            let expectedDirectionX = cos(before.headingRadians)
            let expectedDirectionY = sin(before.headingRadians)
            let signedDistance = selfDX * expectedDirectionX + selfDY * expectedDirectionY
            let observedGain = min(max(
                signedDistance / max(prediction.nominalDisplacement, 0.000_001),
                0
            ), 2)
            learnedForwardGain = Self.approach(learnedForwardGain, observedGain, rate: 0.08)
        }
        if abs(action.turnRateRadiansPerSecond) > 0.08 {
            let observedGain = min(max(
                selfHeadingDelta / Self.nonZero(prediction.nominalHeadingDelta),
                -2
            ), 2)
            learnedTurnGain = Self.approach(learnedTurnGain, observedGain, rate: 0.12)
        }
    }

    private static func summary(
        attribution: SelfCausalAttribution,
        behavior: FlyBehavior,
        predictionError: Double,
        sensorReliability: Double
    ) -> String {
        if sensorReliability < 0.45 {
            return "感觉证据受限，降低对" + behavior.displayName + "后果判断的置信度"
        }
        switch attribution {
        case .selfGenerated:
            return behavior.displayName + "的身体结果与运动副本预测一致，归因为自身行动"
        case .external:
            return "身体变化明显超出" + behavior.displayName + "的预测范围，归因为外界事件"
        case .mixed:
            return "检测到外界触发，同时识别到" + behavior.displayName + "的自身运动响应"
        case .uncertain:
            return predictionError > 0.4
                ? "预测与结果存在偏差，暂不确定变化来源"
                : "当前行动与身体变化都较弱，保留因果判断"
        }
    }

    private static func approach(_ value: Double, _ target: Double, rate: Double) -> Double {
        value + (target - value) * min(max(rate, 0), 1)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        var result = angle
        while result > .pi { result -= .pi * 2 }
        while result < -.pi { result += .pi * 2 }
        return result
    }

    private static func nonZero(_ value: Double) -> Double {
        abs(value) < 0.000_001 ? (value < 0 ? -0.000_001 : 0.000_001) : value
    }

    private static func compactedEpisodes(
        _ source: [FunctionalSelfEpisode]
    ) -> [FunctionalSelfEpisode] {
        var compacted: [FunctionalSelfEpisode] = []
        for episode in source {
            if let previous = compacted.last,
               episode.tick <= previous.tick + 10,
               episode.behavior == previous.behavior,
               episode.attribution == previous.attribution,
               episode.summary == previous.summary {
                compacted[compacted.count - 1] = episode
            } else {
                compacted.append(episode)
            }
        }
        return Array(compacted.suffix(FunctionalSelfState.maximumEpisodeCount))
    }
}

// MARK: - v1.3 ... v1.5 cumulative cognitive self model

public struct CognitiveActionGuidance: Equatable, Sendable {
    public let preferredBehavior: FlyBehavior?
    public let planningConfidence: Double
    public let epistemicDrive: Double
    public let socialApproachDrive: Double
    public let socialAvoidanceDrive: Double

    public init(
        preferredBehavior: FlyBehavior?,
        planningConfidence: Double,
        epistemicDrive: Double,
        socialApproachDrive: Double,
        socialAvoidanceDrive: Double
    ) {
        self.preferredBehavior = preferredBehavior
        self.planningConfidence = Self.clamp(planningConfidence)
        self.epistemicDrive = Self.clamp(epistemicDrive)
        self.socialApproachDrive = Self.clamp(socialApproachDrive)
        self.socialAvoidanceDrive = Self.clamp(socialAvoidanceDrive)
    }

    public static let neutral = CognitiveActionGuidance(
        preferredBehavior: nil,
        planningConfidence: 0,
        epistemicDrive: 0,
        socialApproachDrive: 0,
        socialAvoidanceDrive: 0
    )

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// Cumulative engineered model for the three post-v1.2 milestones:
/// counterfactual/metacognitive self (v1.3), goal/semantic self (v1.4), and
/// self/other distinction (v1.5). MaleCNS constrains its upstream readouts but
/// does not supply these states or their update rules.
public struct DevelopmentalSelfModel: Sendable {
    public static let circuitID =
        "ENG-SELF-PREDICT↔ENG-COUNTERFACTUAL↔ENG-SEMANTIC-SELF↔ENG-OTHER-MODEL→ENG-ACTION-WTA"
    public static let provenance =
        "engineered/modelled; constrained by MaleCNS-derived sensory, central-complex and descending readouts"

    public let individualID: UUID
    public let counterfactualEnabled: Bool
    public let semanticEnabled: Bool
    public let socialEnabled: Bool

    private var counterfactualState: CounterfactualSelfState
    private var semanticState: SemanticSelfState
    private var socialState: SocialSelfState
    private var activeGoal: LongTermSelfGoal
    private var goalSinceTick: UInt64
    private var semanticRevision: UInt64
    private var preferences: SelfPreferenceProfile
    private var beliefs: [SemanticSelfBelief]
    private var consolidationCount: Int
    private var correctCalibrationCount: Int
    private var decisionConfidenceSum: Double
    private var brierScoreSum: Double
    private var blindExternalEventCount: Int
    private var selfHypothesisProbability: Double
    private var worldHypothesisProbability: Double
    private var otherAgencyProbability: Double
    private var predictedOtherResponse: Double
    private var affiliation: Double
    private var vigilance: Double
    private var socialEpisodeCount: Int
    private var lastOtherPresent: Bool
    private var lastSocialAttribution: SelfOtherAttribution

    public init(
        individualID: UUID,
        counterfactualEnabled: Bool = true,
        semanticEnabled: Bool = true,
        socialEnabled: Bool = true,
        restoringCounterfactual: CounterfactualSelfState? = nil,
        restoringSemantic: SemanticSelfState? = nil,
        restoringSocial: SocialSelfState? = nil
    ) {
        self.individualID = individualID
        self.counterfactualEnabled = counterfactualEnabled
        self.semanticEnabled = semanticEnabled
        self.socialEnabled = socialEnabled

        let counterfactual = restoringCounterfactual.flatMap {
            $0.individualID == individualID && $0.enabled ? $0 : nil
        } ?? CounterfactualSelfState.initial(
            individualID: individualID,
            enabled: counterfactualEnabled
        )
        let semantic = restoringSemantic.flatMap {
            $0.individualID == individualID && $0.enabled ? $0 : nil
        } ?? SemanticSelfState.initial(
            individualID: individualID,
            enabled: semanticEnabled
        )
        let social = restoringSocial.flatMap {
            $0.individualID == individualID && $0.enabled ? $0 : nil
        } ?? SocialSelfState.initial(
            individualID: individualID,
            enabled: socialEnabled
        )

        counterfactualState = counterfactualEnabled
            ? counterfactual
            : CounterfactualSelfState.initial(individualID: individualID, enabled: false)
        semanticState = semanticEnabled
            ? semantic
            : SemanticSelfState.initial(individualID: individualID, enabled: false)
        socialState = socialEnabled
            ? social
            : SocialSelfState.initial(individualID: individualID, enabled: false)
        activeGoal = semantic.activeGoal
        goalSinceTick = semantic.goalSinceTick
        semanticRevision = semantic.revision
        preferences = semantic.preferences
        beliefs = semantic.beliefs
        consolidationCount = semantic.consolidationCount
        correctCalibrationCount = Int(
            (counterfactual.calibrationAccuracy
                * Double(counterfactual.calibrationSampleCount)).rounded()
        )
        decisionConfidenceSum = counterfactual.meanDecisionConfidence
            * Double(counterfactual.calibrationSampleCount)
        brierScoreSum = counterfactual.brierScore
            * Double(counterfactual.calibrationSampleCount)
        blindExternalEventCount = counterfactual.blindExternalEventCount
        selfHypothesisProbability = counterfactual.selfHypothesisProbability
        worldHypothesisProbability = counterfactual.worldHypothesisProbability
        otherAgencyProbability = social.otherAgencyProbability
        predictedOtherResponse = social.predictedOtherResponse
        affiliation = social.affiliation
        vigilance = social.vigilance
        socialEpisodeCount = social.socialEpisodeCount
        lastOtherPresent = social.otherPresent
        lastSocialAttribution = social.attribution
    }

    public var counterfactual: CounterfactualSelfState { counterfactualState }
    public var semantic: SemanticSelfState { semanticState }
    public var social: SocialSelfState { socialState }

    public mutating func prepare(
        body: SelfBodyObservation,
        functionalSelf: FunctionalSelfState,
        stimulus: FlyStimulus,
        curiosity: Double,
        arousal: Double,
        tick: UInt64
    ) -> CognitiveActionGuidance {
        updateSocialPerception(
            functionalSelf: functionalSelf,
            stimulus: stimulus,
            tick: tick
        )
        updateGoal(
            body: body,
            functionalSelf: functionalSelf,
            stimulus: stimulus,
            tick: tick
        )

        let epistemicDrive = Self.clamp(
            functionalSelf.uncertainty * 0.64
                + (1 - abs(selfHypothesisProbability - worldHypothesisProbability)) * 0.36
        )
        let candidates = evaluateCandidates(
            body: body,
            functionalSelf: functionalSelf,
            stimulus: stimulus,
            curiosity: curiosity,
            arousal: arousal,
            epistemicDrive: epistemicDrive
        )
        let ranked = candidates.sorted {
            if $0.expectedUtility == $1.expectedUtility {
                return $0.behavior.rawValue < $1.behavior.rawValue
            }
            return $0.expectedUtility > $1.expectedUtility
        }
        let selected = ranked.first
        let gap = max(
            0,
            (ranked.first?.expectedUtility ?? 0)
                - (ranked.dropFirst().first?.expectedUtility ?? 0)
        )
        let planningConfidence = Self.clamp(
            0.38 + gap * 1.6 + functionalSelf.confidence * 0.28
        )
        let shouldProbe = counterfactualEnabled
            && epistemicDrive > 0.50
            && activeGoal != .avoidThreat
            && activeGoal != .maintainEnergy
        let selectedBehavior: FlyBehavior
        if counterfactualEnabled {
            selectedBehavior = shouldProbe ? .exploring : (selected?.behavior ?? .exploring)
        } else if semanticEnabled {
            selectedBehavior = Self.behavior(for: activeGoal, stimulus: stimulus)
        } else {
            selectedBehavior = .idle
        }

        if counterfactualEnabled {
            let previousCounterfactual = counterfactualState
            counterfactualState = CounterfactualSelfState(
                individualID: individualID,
                enabled: true,
                revision: previousCounterfactual.revision &+ 1,
                candidates: candidates,
                selectedBehavior: selectedBehavior,
                selectedActionNeuron: EmbodiedNeuralController.actionNeuronID(for: selectedBehavior),
                selfHypothesisProbability: selfHypothesisProbability,
                worldHypothesisProbability: worldHypothesisProbability,
                ambiguity: 1 - abs(selfHypothesisProbability - worldHypothesisProbability),
                epistemicDrive: epistemicDrive,
                shouldProbe: shouldProbe,
                calibrationSampleCount: previousCounterfactual.calibrationSampleCount,
                calibrationAccuracy: previousCounterfactual.calibrationAccuracy,
                meanDecisionConfidence: previousCounterfactual.meanDecisionConfidence,
                brierScore: previousCounterfactual.brierScore,
                calibrationError: previousCounterfactual.calibrationError,
                blindExternalEventCount: blindExternalEventCount,
                explanation: shouldProbe
                    ? "因果假设接近或感觉证据不足，优先选择低成本探索以获取信息"
                    : "比较 \(candidates.count) 个候选未来后，优先 \(selectedBehavior.displayName)"
            )
        }

        let socialApproach = socialEnabled && socialState.otherPresent
            ? Self.clamp(affiliation * otherAgencyProbability * (1 - stimulus.otherAgentThreat))
            : 0
        let socialAvoidance = socialEnabled && socialState.otherPresent
            ? Self.clamp(max(stimulus.otherAgentThreat, vigilance * 0.65))
            : 0
        return CognitiveActionGuidance(
            preferredBehavior: counterfactualEnabled || semanticEnabled
                ? selectedBehavior : nil,
            planningConfidence: counterfactualEnabled
                ? planningConfidence : (semanticEnabled ? 0.44 : 0),
            epistemicDrive: counterfactualEnabled ? epistemicDrive : 0,
            socialApproachDrive: socialApproach,
            socialAvoidanceDrive: socialAvoidance
        )
    }

    public mutating func observe(
        functionalSelf: FunctionalSelfState,
        selectedAction: SelfActionCommand,
        bodyBefore: SelfBodyObservation,
        bodyAfter: SelfBodyObservation,
        stimulus: FlyStimulus,
        externalCauseForEvaluation: Bool? = nil,
        wasBlindExternalEvent: Bool = false,
        tick: UInt64
    ) {
        updateCounterfactualOutcome(
            functionalSelf: functionalSelf,
            selectedAction: selectedAction,
            stimulus: stimulus,
            externalCauseForEvaluation: externalCauseForEvaluation,
            wasBlindExternalEvent: wasBlindExternalEvent
        )
        updateSemanticKnowledge(
            functionalSelf: functionalSelf,
            selectedAction: selectedAction,
            bodyBefore: bodyBefore,
            bodyAfter: bodyAfter,
            stimulus: stimulus,
            tick: tick
        )
        updateSocialOutcome(
            functionalSelf: functionalSelf,
            selectedAction: selectedAction,
            stimulus: stimulus,
            tick: tick
        )
    }

    private mutating func updateCounterfactualOutcome(
        functionalSelf: FunctionalSelfState,
        selectedAction: SelfActionCommand,
        stimulus: FlyStimulus,
        externalCauseForEvaluation: Bool?,
        wasBlindExternalEvent: Bool
    ) {
        guard counterfactualEnabled else {
            counterfactualState = .initial(individualID: individualID, enabled: false)
            return
        }
        let motorStrength = Self.clamp(
            selectedAction.forwardSpeed / 0.13
                + abs(selectedAction.turnRateRadiansPerSecond) / 4 * 0.35
                + selectedAction.wingDrive * 0.35
        )
        let externalCue = max(
            stimulus.touch,
            stimulus.threat,
            stimulus.contamination * 0.55,
            stimulus.otherAgentThreat * stimulus.otherAgentPresence
        )
        var selfEvidence = (1 - functionalSelf.predictionError)
            * (0.30 + motorStrength * 0.70)
            * functionalSelf.sensorReliability
        var worldEvidence = functionalSelf.predictionError * 0.78
            + externalCue * 0.22
        if functionalSelf.causalAttribution == .selfGenerated { selfEvidence += 0.18 }
        if functionalSelf.causalAttribution == .external { worldEvidence += 0.18 }
        if functionalSelf.causalAttribution == .mixed {
            selfEvidence += 0.10
            worldEvidence += 0.10
        }
        let evidenceTotal = max(selfEvidence + worldEvidence, 0.000_001)
        let instantaneousSelf = Self.clamp(selfEvidence / evidenceTotal)
        let hypothesisUpdateRate = functionalSelf.causalAttribution == .external
            ? 0.84 : 0.52
        selfHypothesisProbability = Self.approach(
            selfHypothesisProbability,
            instantaneousSelf,
            rate: hypothesisUpdateRate
        )
        worldHypothesisProbability = 1 - selfHypothesisProbability

        var sampleCount = counterfactualState.calibrationSampleCount
        var accuracy = counterfactualState.calibrationAccuracy
        var meanConfidence = counterfactualState.meanDecisionConfidence
        var brierScore = counterfactualState.brierScore
        var calibrationError = counterfactualState.calibrationError
        if let externalCauseForEvaluation {
            sampleCount += 1
            let predictedExternal = worldHypothesisProbability >= selfHypothesisProbability
            if predictedExternal == externalCauseForEvaluation {
                correctCalibrationCount += 1
            }
            let decisionConfidence = max(
                selfHypothesisProbability,
                worldHypothesisProbability
            )
            decisionConfidenceSum += decisionConfidence
            let target = externalCauseForEvaluation ? 1.0 : 0.0
            let squaredError = pow(worldHypothesisProbability - target, 2)
            brierScoreSum += squaredError
            accuracy = Double(correctCalibrationCount) / Double(sampleCount)
            meanConfidence = decisionConfidenceSum / Double(sampleCount)
            brierScore = brierScoreSum / Double(sampleCount)
            calibrationError = abs(accuracy - meanConfidence)
            if wasBlindExternalEvent, externalCauseForEvaluation, predictedExternal {
                blindExternalEventCount += 1
            }
        }

        let ambiguity = 1 - abs(selfHypothesisProbability - worldHypothesisProbability)
        let epistemicDrive = Self.clamp(
            functionalSelf.uncertainty * 0.64 + ambiguity * 0.36
        )
        let previousCounterfactual = counterfactualState
        // Rebuild the small nine-item value array instead of sharing its COW
        // storage while replacing a large optimized struct. This also keeps a
        // returned snapshot independent from the model's next update.
        let retainedCandidates = previousCounterfactual.candidates.map {
            CounterfactualActionEvaluation(
                behavior: $0.behavior,
                actionNeuron: $0.actionNeuron,
                predictedDisplacement: $0.predictedDisplacement,
                predictedEnergyCost: $0.predictedEnergyCost,
                predictedThreatExposure: $0.predictedThreatExposure,
                expectedInformationGain: $0.expectedInformationGain,
                expectedUtility: $0.expectedUtility,
                confidence: $0.confidence
            )
        }
        counterfactualState = CounterfactualSelfState(
            individualID: individualID,
            enabled: true,
            revision: previousCounterfactual.revision &+ 1,
            candidates: retainedCandidates,
            selectedBehavior: previousCounterfactual.selectedBehavior,
            selectedActionNeuron: previousCounterfactual.selectedActionNeuron,
            selfHypothesisProbability: selfHypothesisProbability,
            worldHypothesisProbability: worldHypothesisProbability,
            ambiguity: ambiguity,
            epistemicDrive: epistemicDrive,
            shouldProbe: epistemicDrive > 0.50,
            calibrationSampleCount: sampleCount,
            calibrationAccuracy: accuracy,
            meanDecisionConfidence: meanConfidence,
            brierScore: brierScore,
            calibrationError: calibrationError,
            blindExternalEventCount: blindExternalEventCount,
            explanation: worldHypothesisProbability > selfHypothesisProbability
                ? "未读取实验标签，仅凭行动预测残差，当前更支持外界原因假设"
                : "行动结果与运动副本较一致，当前更支持自身原因假设"
        )
    }

    private mutating func updateGoal(
        body: SelfBodyObservation,
        functionalSelf: FunctionalSelfState,
        stimulus: FlyStimulus,
        tick: UInt64
    ) {
        guard semanticEnabled else {
            semanticState = .initial(individualID: individualID, enabled: false)
            return
        }
        let desired: LongTermSelfGoal
        if max(stimulus.threat, stimulus.touch, stimulus.otherAgentThreat) > 0.55 {
            desired = .avoidThreat
        } else if body.energy < 0.38 || stimulus.foodContact > 0.5 {
            desired = .maintainEnergy
        } else if body.groomingNeed > 0.55 || stimulus.contamination > 0.5 {
            desired = .restoreBody
        } else if stimulus.otherAgentPresence > 0.45 {
            desired = .observeOther
        } else if functionalSelf.uncertainty > 0.54 {
            desired = .reduceUncertainty
        } else {
            desired = .exploreWorld
        }

        let heldTicks = tick >= goalSinceTick ? tick - goalSinceTick : 0
        let urgent = Self.goalPriority(desired) > Self.goalPriority(activeGoal)
        if desired != activeGoal, urgent || heldTicks >= 20 {
            activeGoal = desired
            goalSinceTick = tick
            semanticRevision &+= 1
        }
        let stability = Self.clamp(Double(heldTicks) / 60)
        semanticState = SemanticSelfState(
            individualID: individualID,
            enabled: true,
            revision: semanticRevision,
            activeGoal: activeGoal,
            goalSinceTick: goalSinceTick,
            goalStability: stability,
            preferences: preferences,
            beliefs: beliefs,
            consolidationCount: consolidationCount,
            narrativeSummary: "当前长期目标是\(activeGoal.displayName)，已持续 \(heldTicks) 个计算周期"
        )
    }

    private mutating func updateSemanticKnowledge(
        functionalSelf: FunctionalSelfState,
        selectedAction: SelfActionCommand,
        bodyBefore: SelfBodyObservation,
        bodyAfter: SelfBodyObservation,
        stimulus: FlyStimulus,
        tick: UInt64
    ) {
        guard semanticEnabled else { return }
        let safeExploration = selectedAction.behavior == .exploring
            && max(stimulus.threat, stimulus.otherAgentThreat) < 0.25
        let explorationTarget = safeExploration ? 0.78 : preferences.exploration
        let cautionTarget = Self.clamp(
            worldHypothesisProbability * 0.62
                + max(stimulus.threat, stimulus.otherAgentThreat) * 0.38
        )
        let conservationTarget = Self.clamp(
            (1 - bodyAfter.energy) * 0.62 + bodyAfter.fatigue * 0.38
        )
        let cleanlinessTarget = Self.clamp(
            bodyAfter.groomingNeed * 0.55
                + (selectedAction.behavior == .groomingHead
                    || selectedAction.behavior == .groomingWings ? 0.45 : 0)
        )
        let socialTarget = stimulus.otherAgentPresence > 0.3
            ? Self.clamp((1 - stimulus.otherAgentThreat) * stimulus.otherAgentContingency)
            : preferences.socialInterest
        preferences = SelfPreferenceProfile(
            exploration: Self.approach(preferences.exploration, explorationTarget, rate: 0.025),
            caution: Self.approach(preferences.caution, cautionTarget, rate: 0.035),
            energyConservation: Self.approach(
                preferences.energyConservation,
                conservationTarget,
                rate: 0.025
            ),
            cleanliness: Self.approach(preferences.cleanliness, cleanlinessTarget, rate: 0.025),
            socialInterest: Self.approach(preferences.socialInterest, socialTarget, rate: 0.025)
        )

        guard tick.isMultiple(of: 10) else {
            let previousSemantic = semanticState
            semanticState = SemanticSelfState(
                individualID: individualID,
                enabled: true,
                revision: semanticRevision,
                activeGoal: activeGoal,
                goalSinceTick: goalSinceTick,
                goalStability: previousSemantic.goalStability,
                preferences: preferences,
                beliefs: beliefs,
                consolidationCount: consolidationCount,
                narrativeSummary: previousSemantic.narrativeSummary
            )
            return
        }

        consolidationCount += 1
        semanticRevision &+= 1
        let motorReliability = Self.clamp(
            (functionalSelf.learnedForwardGain + abs(functionalSelf.learnedTurnGain)) / 2
        )
        beliefs = [
            updatedBelief(
                key: "motor-control",
                name: "身体控制可靠性",
                observedValue: motorReliability,
                summary: "依据运动副本与位移/转向后果整合"
            ),
            updatedBelief(
                key: "sensory-trust",
                name: "感觉证据可信度",
                observedValue: functionalSelf.sensorReliability,
                summary: "依据多通道感觉可靠度整合"
            ),
            updatedBelief(
                key: "external-volatility",
                name: "环境外力波动",
                observedValue: worldHypothesisProbability,
                summary: "依据无法由自身行动解释的状态变化整合"
            ),
            updatedBelief(
                key: "social-contingency",
                name: "他者响应关联",
                observedValue: otherAgencyProbability,
                summary: "依据他者运动与自身行动的时序关联整合"
            )
        ]
        let energyTrend = bodyAfter.energy - bodyBefore.energy
        let evidenceSummary = energyTrend < -0.001
            ? "能量正在下降，优先维护身体预算"
            : "身体预算稳定，可继续当前目标"
        let previousSemantic = semanticState
        semanticState = SemanticSelfState(
            individualID: individualID,
            enabled: true,
            revision: semanticRevision,
            activeGoal: activeGoal,
            goalSinceTick: goalSinceTick,
            goalStability: previousSemantic.goalStability,
            preferences: preferences,
            beliefs: beliefs,
            consolidationCount: consolidationCount,
            narrativeSummary: "我模型的长期目标为\(activeGoal.displayName)；\(evidenceSummary)。这是状态摘要，不是主观自述。"
        )
    }

    private mutating func updateSocialPerception(
        functionalSelf: FunctionalSelfState,
        stimulus: FlyStimulus,
        tick: UInt64
    ) {
        guard socialEnabled else {
            socialState = .initial(individualID: individualID, enabled: false)
            return
        }
        let presence = stimulus.otherAgentPresence
        let otherPresent = presence > 0.20
        let agencyEvidence = Self.clamp(
            presence
                * (stimulus.otherAgentMotion * 0.44
                    + stimulus.otherAgentContingency * 0.56)
                * (1 - stimulus.otherAgentThreat * 0.22)
        )
        otherAgencyProbability = Self.approach(
            otherAgencyProbability,
            otherPresent ? agencyEvidence : 0,
            rate: otherPresent ? 0.34 : 0.12
        )
        predictedOtherResponse = Self.approach(
            predictedOtherResponse,
            otherPresent ? stimulus.otherAgentContingency : 0,
            rate: 0.18
        )
        let separation = otherPresent
            ? Self.clamp(
                0.34
                    + abs(functionalSelf.proprioceptiveChannel - stimulus.otherAgentMotion) * 0.32
                    + otherAgencyProbability * 0.34
            )
            : 0.82
        let previousSocial = socialState
        socialState = SocialSelfState(
            individualID: individualID,
            enabled: true,
            revision: previousSocial.revision &+ 1,
            otherPresent: otherPresent,
            trackedOtherID: otherPresent ? (stimulus.otherAgentID ?? "OTHER-UNRESOLVED") : nil,
            selfOtherSeparation: separation,
            otherAgencyProbability: otherAgencyProbability,
            predictedOtherResponse: predictedOtherResponse,
            observedOtherMotion: stimulus.otherAgentMotion,
            affiliation: affiliation,
            vigilance: vigilance,
            jointActionProbability: previousSocial.jointActionProbability,
            attribution: previousSocial.attribution,
            socialEpisodeCount: socialEpisodeCount,
            explanation: otherPresent
                ? "检测到独立运动线索，正在估计他者能动性与响应关系"
                : "当前没有稳定的他者线索"
        )
        _ = tick
    }

    private mutating func updateSocialOutcome(
        functionalSelf: FunctionalSelfState,
        selectedAction: SelfActionCommand,
        stimulus: FlyStimulus,
        tick: UInt64
    ) {
        guard socialEnabled else { return }
        let otherPresent = stimulus.otherAgentPresence > 0.20
        let jointProbability = otherPresent
            ? Self.clamp(
                otherAgencyProbability
                    * functionalSelf.agencyScore
                    * stimulus.otherAgentContingency
            )
            : 0
        let attribution: SelfOtherAttribution
        if otherPresent,
           jointProbability > 0.48,
           selectedAction.forwardSpeed + abs(selectedAction.turnRateRadiansPerSecond) > 0.008 {
            attribution = .joint
        } else if otherPresent, otherAgencyProbability > 0.50 {
            attribution = .otherAgent
        } else if !otherPresent, functionalSelf.causalAttribution == .external {
            attribution = .environment
        } else if functionalSelf.causalAttribution == .selfGenerated {
            attribution = .selfAgent
        } else {
            attribution = .uncertain
        }
        let affiliationTarget = otherPresent
            ? Self.clamp(
                (1 - stimulus.otherAgentThreat) * 0.62
                    + stimulus.otherAgentContingency * 0.38
            )
            : affiliation
        affiliation = Self.approach(affiliation, affiliationTarget, rate: 0.06)
        vigilance = Self.approach(
            vigilance,
            otherPresent ? max(stimulus.otherAgentThreat, 1 - affiliation) : 0,
            rate: 0.10
        )
        if otherPresent != lastOtherPresent
            || (otherPresent && attribution != lastSocialAttribution && tick.isMultiple(of: 5)) {
            socialEpisodeCount += 1
        }
        lastOtherPresent = otherPresent
        lastSocialAttribution = attribution
        let previousSocial = socialState
        socialState = SocialSelfState(
            individualID: individualID,
            enabled: true,
            revision: previousSocial.revision &+ 1,
            otherPresent: otherPresent,
            trackedOtherID: otherPresent ? (stimulus.otherAgentID ?? "OTHER-UNRESOLVED") : nil,
            selfOtherSeparation: previousSocial.selfOtherSeparation,
            otherAgencyProbability: otherAgencyProbability,
            predictedOtherResponse: predictedOtherResponse,
            observedOtherMotion: stimulus.otherAgentMotion,
            affiliation: affiliation,
            vigilance: vigilance,
            jointActionProbability: jointProbability,
            attribution: attribution,
            socialEpisodeCount: socialEpisodeCount,
            explanation: Self.socialExplanation(attribution, otherID: stimulus.otherAgentID)
        )
    }

    private func evaluateCandidates(
        body: SelfBodyObservation,
        functionalSelf: FunctionalSelfState,
        stimulus: FlyStimulus,
        curiosity: Double,
        arousal: Double,
        epistemicDrive: Double
    ) -> [CounterfactualActionEvaluation] {
        let behaviors: [FlyBehavior] = [
            .idle, .exploring, .walking, .foraging, .feeding,
            .flying, .groomingHead, .resting, .startled
        ]
        return behaviors.map { behavior in
            let profile = Self.candidateProfile(
                behavior,
                stimulus: stimulus,
                body: body
            )
            let goalFit = Self.goalFit(
                behavior,
                goal: activeGoal,
                stimulus: stimulus
            )
            let explorationFit = behavior == .exploring || behavior == .walking
                ? preferences.exploration * 0.18 : 0
            let cautionFit = behavior == .startled || behavior == .idle
                ? preferences.caution * stimulus.threat * 0.20 : 0
            let cleanlinessFit = behavior == .groomingHead
                ? preferences.cleanliness * body.groomingNeed * 0.22 : 0
            let socialFit = behavior == .exploring && stimulus.otherAgentPresence > 0.2
                ? preferences.socialInterest * (1 - stimulus.otherAgentThreat) * 0.24 : 0
            let informationValue = profile.informationGain * epistemicDrive * 0.32
            let foodValue = profile.foodBenefit * (1 - body.energy) * 0.52
            let safetyValue = (1 - profile.threatExposure)
                * max(stimulus.threat, stimulus.otherAgentThreat) * 0.32
            let energyPenalty = profile.energyCost
                * (0.7 + preferences.energyConservation * 0.8)
            let threatPenalty = profile.threatExposure
                * (0.35 + preferences.caution * 0.55)
            let utility = Self.clampSigned(
                goalFit * 0.55
                    + informationValue + foodValue + safetyValue
                    + explorationFit + cautionFit + cleanlinessFit + socialFit
                    + curiosity * (behavior == .exploring ? 0.12 : 0)
                    + arousal * (behavior == .flying ? 0.05 : 0)
                    - energyPenalty - threatPenalty
            )
            return CounterfactualActionEvaluation(
                behavior: behavior,
                actionNeuron: EmbodiedNeuralController.actionNeuronID(for: behavior),
                predictedDisplacement: profile.displacement,
                predictedEnergyCost: profile.energyCost,
                predictedThreatExposure: profile.threatExposure,
                expectedInformationGain: profile.informationGain,
                expectedUtility: utility,
                confidence: Self.clamp(
                    0.36
                        + functionalSelf.confidence * 0.42
                        + (1 - profile.threatExposure) * 0.22
                )
            )
        }
    }

    private func updatedBelief(
        key: String,
        name: String,
        observedValue: Double,
        summary: String
    ) -> SemanticSelfBelief {
        let prior = beliefs.first { $0.key == key }
        let value = Self.approach(
            prior?.value ?? observedValue,
            observedValue,
            rate: 0.16
        )
        let count = (prior?.evidenceCount ?? 0) + 1
        let confidence = Self.clamp(1 - exp(-Double(count) / 8))
        return SemanticSelfBelief(
            key: key,
            displayName: name,
            value: value,
            confidence: confidence,
            evidenceCount: count,
            summary: summary
        )
    }

    private static func behavior(
        for goal: LongTermSelfGoal,
        stimulus: FlyStimulus
    ) -> FlyBehavior {
        switch goal {
        case .maintainEnergy: stimulus.foodContact > 0.5 ? .feeding : .foraging
        case .avoidThreat: .startled
        case .exploreWorld, .reduceUncertainty, .observeOther: .exploring
        case .restoreBody: .groomingHead
        }
    }

    private static func goalPriority(_ goal: LongTermSelfGoal) -> Int {
        switch goal {
        case .avoidThreat: 6
        case .maintainEnergy: 5
        case .restoreBody: 4
        case .reduceUncertainty: 3
        case .observeOther: 2
        case .exploreWorld: 1
        }
    }

    private static func goalFit(
        _ behavior: FlyBehavior,
        goal: LongTermSelfGoal,
        stimulus: FlyStimulus
    ) -> Double {
        switch goal {
        case .maintainEnergy:
            if stimulus.foodContact > 0.5 { return behavior == .feeding ? 1 : 0.10 }
            if behavior == .foraging { return 1 }
            return behavior == .resting ? 0.42 : 0.08
        case .avoidThreat:
            if behavior == .startled { return 1 }
            return behavior == .flying ? 0.62 : 0.05
        case .exploreWorld:
            if behavior == .exploring { return 1 }
            return behavior == .walking || behavior == .flying ? 0.62 : 0.08
        case .restoreBody:
            return behavior == .groomingHead ? 1 : (behavior == .resting ? 0.34 : 0.06)
        case .reduceUncertainty:
            if behavior == .exploring { return 1 }
            return behavior == .idle ? 0.48 : 0.08
        case .observeOther:
            if behavior == .exploring { return 1 }
            return behavior == .walking ? 0.70 : 0.08
        }
    }

    private static func candidateProfile(
        _ behavior: FlyBehavior,
        stimulus: FlyStimulus,
        body: SelfBodyObservation
    ) -> (
        displacement: Double,
        energyCost: Double,
        threatExposure: Double,
        informationGain: Double,
        foodBenefit: Double
    ) {
        let threat = max(stimulus.threat, stimulus.otherAgentThreat)
        switch behavior {
        case .idle: return (0, 0.003, threat * 0.86, 0.24, 0)
        case .exploring: return (0.045, 0.018, threat * 0.62, 0.92, stimulus.foodOdor * 0.24)
        case .walking: return (0.065, 0.023, threat * 0.72, 0.58, stimulus.foodOdor * 0.35)
        case .foraging: return (0.055, 0.026, threat * 0.68, 0.55, 0.34 + stimulus.foodOdor * 0.66)
        case .avoidingOdor: return (0.052, 0.024, threat * 0.45, 0.42, 0)
        case .feeding: return (0, 0.006, threat * 0.95, 0.10, stimulus.foodContact)
        case .flying: return (0.16, 0.085, threat * 0.22, 0.48, stimulus.foodOdor * 0.10)
        case .groomingHead, .groomingWings:
            return (0, 0.015, threat * 0.92, 0.12, 0)
        case .resting: return (0, 0.001, threat, 0.08, body.energy < 0.2 ? 0.12 : 0)
        case .startled: return (0.12, 0.052, threat * 0.08, 0.30, 0)
        case .torpor: return (0, 0, threat, 0, 0)
        }
    }

    private static func socialExplanation(
        _ attribution: SelfOtherAttribution,
        otherID: String?
    ) -> String {
        let name = otherID ?? "未命名他者"
        switch attribution {
        case .selfAgent: return "当前变化主要与自身运动副本一致"
        case .otherAgent: return "\(name) 的独立运动与响应关系更支持他者原因"
        case .environment: return "变化不随自身或已跟踪他者行动，归为环境事件"
        case .joint: return "自身行动与 \(name) 的条件响应共同解释当前变化"
        case .uncertain: return "自身、他者与环境证据尚不足以形成稳定区分"
        }
    }

    private static func approach(_ value: Double, _ target: Double, rate: Double) -> Double {
        value + (target - value) * min(max(rate, 0), 1)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}
