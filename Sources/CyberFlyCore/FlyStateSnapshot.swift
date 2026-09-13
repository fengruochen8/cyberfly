import Foundation

public enum FlyWidgetKind {
    public static let value = "CyberFlyStateWidget"
}

public enum FlyOdorCue: String, Codable, CaseIterable, Sendable {
    case amber
    case berry

    public var displayName: String {
        switch self {
        case .amber: "琥珀果香"
        case .berry: "莓红果香"
        }
    }

    public var receptorPathway: String {
        switch self {
        case .amber: "ORN_DM1→DM1_lPN"
        case .berry: "ORN_DM2→DM2_lPN"
        }
    }
}

public enum FlyLifeState: String, Codable, CaseIterable, Sendable {
    case active
    case torpor
    case dead

    public var displayName: String {
        switch self {
        case .active: "活动中"
        case .torpor: "濒死休眠"
        case .dead: "已死亡"
        }
    }
}

public enum FlyBehavior: String, Codable, CaseIterable, Sendable {
    case idle
    case exploring
    case walking
    case foraging
    case avoidingOdor
    case feeding
    case flying
    case groomingHead
    case groomingWings
    case resting
    case startled
    case torpor

    public var displayName: String {
        switch self {
        case .idle: "停留观察"
        case .exploring: "探索环境"
        case .walking: "自主行走"
        case .foraging: "寻找食物"
        case .avoidingOdor: "回避气味"
        case .feeding: "正在进食"
        case .flying: "正在飞行"
        case .groomingHead: "梳理头部"
        case .groomingWings: "梳理翅膀"
        case .resting: "休息"
        case .startled: "受惊回避"
        case .torpor: "濒死休眠"
        }
    }

    public var systemImage: String {
        switch self {
        case .idle: "eye"
        case .exploring: "safari"
        case .walking: "figure.walk"
        case .foraging: "leaf"
        case .avoidingOdor: "arrow.uturn.backward"
        case .feeding: "fork.knife"
        case .flying: "wind"
        case .groomingHead, .groomingWings: "sparkles"
        case .resting: "moon.zzz"
        case .startled: "exclamationmark.triangle"
        case .torpor: "heart.slash"
        }
    }
}

public enum FlyEmotion: String, Codable, CaseIterable, Sendable {
    case happy
    case content
    case curious
    case calm
    case alert
    case hungry
    case tired
    case distressed
    case dormant

    public var displayName: String {
        switch self {
        case .happy: "开心"
        case .content: "满足"
        case .curious: "好奇"
        case .calm: "平静"
        case .alert: "警觉"
        case .hungry: "饥饿"
        case .tired: "疲倦"
        case .distressed: "不安"
        case .dormant: "休眠"
        }
    }
}

public enum ModelFidelity: String, Codable, Sendable {
    case bootstrap = "bootstrap-v0.1"
    case hybridConnectome = "male-cns-hybrid-v0.2"
    case hybridLearning = "male-cns-learning-v0.3"
    case embodiedNeural = "male-cns-neural-embodied-v0.4"
    case connectomeConstrained = "male-cns-connectome"
    case wholeCNSDigitalFly = "male-cns-whole-cns-v1.0"
    case functionalSelfCognition = "male-cns-functional-self-v1.2"
    case counterfactualSelfCognition = "male-cns-counterfactual-self-v1.3"
    case semanticSelfCognition = "male-cns-semantic-self-v1.4"
    case socialSelfCognition = "male-cns-social-self-v1.5"

    public var displayName: String {
        switch self {
        case .bootstrap: "自主状态基础模型"
        case .hybridConnectome: "MaleCNS 视觉回路混合模型"
        case .hybridLearning: "MaleCNS 视觉与学习回路混合模型"
        case .embodiedNeural: "MaleCNS 约束的全动作神经模型"
        case .connectomeConstrained: "MaleCNS 连接组约束模型"
        case .wholeCNSDigitalFly: "MaleCNS 全 CNS 数字果蝇"
        case .functionalSelfCognition: "MaleCNS 约束的功能性自我模型"
        case .counterfactualSelfCognition: "反事实与元认知自我模型"
        case .semanticSelfCognition: "长期目标与语义自我模型"
        case .socialSelfCognition: "自己 / 他者认知模型"
        }
    }
}

public struct FlyStateSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 9

    public let schemaVersion: Int
    public let individualID: UUID
    public let sampledAt: Date
    public let tick: UInt64
    public let lifeState: FlyLifeState
    public let behavior: FlyBehavior
    public let emotion: FlyEmotion
    public let energy: Double
    public let hunger: Double
    public let valence: Double
    public let wellbeing: Double
    public let curiosity: Double
    public let arousal: Double
    public let fatigue: Double
    public let groomingNeed: Double
    public let wingActivity: Double
    public let neuralActivity: Double
    public let neuralCircuit: String?
    public let activeNeuronCount: Int?
    public let learningCircuit: String?
    public let currentOdorCue: FlyOdorCue?
    public let learnedValence: Double?
    public let memoryConfidence: Double?
    public let activeKenyonCellCount: Int?
    public let rewardDANActivity: Double?
    public let punishmentDANActivity: Double?
    public let memorySummary: String?
    public let controllerCircuit: String?
    public let controllerProvenance: String?
    public let controllerNeuronCount: Int?
    public let activeControllerNeuronCount: Int?
    public let selectedActionNeuron: String?
    public let actionConfidence: Double?
    public let forwardSpeed: Double?
    public let turnRateRadiansPerSecond: Double?
    public let feedingMotorDrive: Double?
    public let groomingMotorDrive: Double?
    public let restMotorDrive: Double?
    public let actionNeuronActivities: [Double]?
    public let wholeCNSDataset: String?
    public let wholeCNSGraphSHA256: String?
    public let wholeCNSNodeCount: Int?
    public let wholeCNSEdgeCount: Int?
    public let wholeCNSActiveNeuronCount: Int?
    public let wholeCNSSpikeCount: Int?
    public let wholeCNSEdgeEventCount: Int?
    public let wholeCNSRealTimeFactor: Double?
    public let wholeCNSSensoryActivity: Double?
    public let wholeCNSCentralComplexActivity: Double?
    public let wholeCNSDescendingActivity: Double?
    public let wholeCNSMotorActivity: Double?
    public let wholeCNSDopamineLevel: Double?
    public let wholeCNSSerotoninLevel: Double?
    public let wholeCNSOctopamineLevel: Double?
    public let wholeCNSPlasticSynapseSourceCount: Int?
    public let wholeCNSEventBudgetSaturated: Bool?
    public let functionalSelf: FunctionalSelfState?
    public let counterfactualSelf: CounterfactualSelfState?
    public let semanticSelf: SemanticSelfState?
    public let socialSelf: SocialSelfState?
    public let positionX: Double
    public let positionY: Double
    public let headingRadians: Double
    public let reason: String
    public let modelFidelity: ModelFidelity

    public init(
        schemaVersion: Int = FlyStateSnapshot.currentSchemaVersion,
        individualID: UUID,
        sampledAt: Date,
        tick: UInt64,
        lifeState: FlyLifeState,
        behavior: FlyBehavior,
        emotion: FlyEmotion,
        energy: Double,
        hunger: Double,
        valence: Double,
        wellbeing: Double,
        curiosity: Double,
        arousal: Double,
        fatigue: Double,
        groomingNeed: Double,
        wingActivity: Double,
        neuralActivity: Double,
        neuralCircuit: String? = nil,
        activeNeuronCount: Int? = nil,
        learningCircuit: String? = nil,
        currentOdorCue: FlyOdorCue? = nil,
        learnedValence: Double? = nil,
        memoryConfidence: Double? = nil,
        activeKenyonCellCount: Int? = nil,
        rewardDANActivity: Double? = nil,
        punishmentDANActivity: Double? = nil,
        memorySummary: String? = nil,
        controllerCircuit: String? = nil,
        controllerProvenance: String? = nil,
        controllerNeuronCount: Int? = nil,
        activeControllerNeuronCount: Int? = nil,
        selectedActionNeuron: String? = nil,
        actionConfidence: Double? = nil,
        forwardSpeed: Double? = nil,
        turnRateRadiansPerSecond: Double? = nil,
        feedingMotorDrive: Double? = nil,
        groomingMotorDrive: Double? = nil,
        restMotorDrive: Double? = nil,
        actionNeuronActivities: [Double]? = nil,
        wholeCNSDataset: String? = nil,
        wholeCNSGraphSHA256: String? = nil,
        wholeCNSNodeCount: Int? = nil,
        wholeCNSEdgeCount: Int? = nil,
        wholeCNSActiveNeuronCount: Int? = nil,
        wholeCNSSpikeCount: Int? = nil,
        wholeCNSEdgeEventCount: Int? = nil,
        wholeCNSRealTimeFactor: Double? = nil,
        wholeCNSSensoryActivity: Double? = nil,
        wholeCNSCentralComplexActivity: Double? = nil,
        wholeCNSDescendingActivity: Double? = nil,
        wholeCNSMotorActivity: Double? = nil,
        wholeCNSDopamineLevel: Double? = nil,
        wholeCNSSerotoninLevel: Double? = nil,
        wholeCNSOctopamineLevel: Double? = nil,
        wholeCNSPlasticSynapseSourceCount: Int? = nil,
        wholeCNSEventBudgetSaturated: Bool? = nil,
        functionalSelf: FunctionalSelfState? = nil,
        counterfactualSelf: CounterfactualSelfState? = nil,
        semanticSelf: SemanticSelfState? = nil,
        socialSelf: SocialSelfState? = nil,
        positionX: Double,
        positionY: Double,
        headingRadians: Double,
        reason: String,
        modelFidelity: ModelFidelity
    ) {
        self.schemaVersion = schemaVersion
        self.individualID = individualID
        self.sampledAt = sampledAt
        self.tick = tick
        self.lifeState = lifeState
        self.behavior = behavior
        self.emotion = emotion
        self.energy = Self.clamp(energy)
        self.hunger = Self.clamp(hunger)
        self.valence = Self.clamp(valence)
        self.wellbeing = Self.clamp(wellbeing)
        self.curiosity = Self.clamp(curiosity)
        self.arousal = Self.clamp(arousal)
        self.fatigue = Self.clamp(fatigue)
        self.groomingNeed = Self.clamp(groomingNeed)
        self.wingActivity = Self.clamp(wingActivity)
        self.neuralActivity = Self.clamp(neuralActivity)
        self.neuralCircuit = neuralCircuit
        self.activeNeuronCount = activeNeuronCount.map { max($0, 0) }
        self.learningCircuit = learningCircuit
        self.currentOdorCue = currentOdorCue
        self.learnedValence = learnedValence.map(Self.clampSigned)
        self.memoryConfidence = memoryConfidence.map(Self.clamp)
        self.activeKenyonCellCount = activeKenyonCellCount.map { max($0, 0) }
        self.rewardDANActivity = rewardDANActivity.map(Self.clamp)
        self.punishmentDANActivity = punishmentDANActivity.map(Self.clamp)
        self.memorySummary = memorySummary
        self.controllerCircuit = controllerCircuit
        self.controllerProvenance = controllerProvenance
        self.controllerNeuronCount = controllerNeuronCount.map { max($0, 0) }
        self.activeControllerNeuronCount = activeControllerNeuronCount.map { max($0, 0) }
        self.selectedActionNeuron = selectedActionNeuron
        self.actionConfidence = actionConfidence.map(Self.clamp)
        self.forwardSpeed = forwardSpeed.map { max($0, 0) }
        self.turnRateRadiansPerSecond = turnRateRadiansPerSecond
        self.feedingMotorDrive = feedingMotorDrive.map(Self.clamp)
        self.groomingMotorDrive = groomingMotorDrive.map(Self.clamp)
        self.restMotorDrive = restMotorDrive.map(Self.clamp)
        self.actionNeuronActivities = actionNeuronActivities?.map(Self.clamp)
        self.wholeCNSDataset = wholeCNSDataset
        self.wholeCNSGraphSHA256 = wholeCNSGraphSHA256
        self.wholeCNSNodeCount = wholeCNSNodeCount.map { max($0, 0) }
        self.wholeCNSEdgeCount = wholeCNSEdgeCount.map { max($0, 0) }
        self.wholeCNSActiveNeuronCount = wholeCNSActiveNeuronCount.map { max($0, 0) }
        self.wholeCNSSpikeCount = wholeCNSSpikeCount.map { max($0, 0) }
        self.wholeCNSEdgeEventCount = wholeCNSEdgeEventCount.map { max($0, 0) }
        self.wholeCNSRealTimeFactor = wholeCNSRealTimeFactor.map { max($0, 0) }
        self.wholeCNSSensoryActivity = wholeCNSSensoryActivity.map(Self.clamp)
        self.wholeCNSCentralComplexActivity = wholeCNSCentralComplexActivity.map(Self.clamp)
        self.wholeCNSDescendingActivity = wholeCNSDescendingActivity.map(Self.clamp)
        self.wholeCNSMotorActivity = wholeCNSMotorActivity.map(Self.clamp)
        self.wholeCNSDopamineLevel = wholeCNSDopamineLevel.map(Self.clamp)
        self.wholeCNSSerotoninLevel = wholeCNSSerotoninLevel.map(Self.clamp)
        self.wholeCNSOctopamineLevel = wholeCNSOctopamineLevel.map(Self.clamp)
        self.wholeCNSPlasticSynapseSourceCount = wholeCNSPlasticSynapseSourceCount.map { max($0, 0) }
        self.wholeCNSEventBudgetSaturated = wholeCNSEventBudgetSaturated
        self.functionalSelf = functionalSelf
        self.counterfactualSelf = counterfactualSelf
        self.semanticSelf = semanticSelf
        self.socialSelf = socialSelf
        self.positionX = Self.clamp(positionX)
        self.positionY = Self.clamp(positionY)
        self.headingRadians = headingRadians
        self.reason = reason
        self.modelFidelity = modelFidelity
    }

    public var displayFingerprint: String {
        [
            lifeState.rawValue,
            behavior.rawValue,
            emotion.rawValue,
            String(Int((hunger * 10).rounded(.down))),
            String(Int((wellbeing * 10).rounded(.down))),
            String(Int((curiosity * 10).rounded(.down))),
            currentOdorCue?.rawValue ?? "none",
            String(Int(((learnedValence ?? 0) * 5).rounded()))
        ].joined(separator: ":")
    }

    public func isStale(relativeTo now: Date = Date(), maximumAge: TimeInterval = 120) -> Bool {
        now.timeIntervalSince(sampledAt) > maximumAge
    }

    public static func unavailable(now: Date = Date()) -> FlyStateSnapshot {
        FlyStateSnapshot(
            individualID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            sampledAt: now,
            tick: 0,
            lifeState: .torpor,
            behavior: .torpor,
            emotion: .dormant,
            energy: 0,
            hunger: 1,
            valence: 0.2,
            wellbeing: 0.2,
            curiosity: 0,
            arousal: 0,
            fatigue: 1,
            groomingNeed: 0,
            wingActivity: 0,
            neuralActivity: 0,
            positionX: 0.5,
            positionY: 0.1,
            headingRadians: 0,
            reason: "等待果蝇宿主写入第一份状态",
            modelFidelity: .bootstrap
        )
    }

    public static func preview(now: Date = Date()) -> FlyStateSnapshot {
        FlyStateSnapshot(
            individualID: UUID(uuidString: "B2B88132-EE6D-47AC-96F2-F30DF3937D6A")!,
            sampledAt: now,
            tick: 4_208,
            lifeState: .active,
            behavior: .exploring,
            emotion: .curious,
            energy: 0.71,
            hunger: 0.29,
            valence: 0.68,
            wellbeing: 0.74,
            curiosity: 0.86,
            arousal: 0.43,
            fatigue: 0.22,
            groomingNeed: 0.31,
            wingActivity: 0.18,
            neuralActivity: 0.52,
            neuralCircuit: "LoVP92→VES200m→DNg13",
            activeNeuronCount: 9,
            learningCircuit: "DM1/DM2→KC→MBON01/11↔PAM01/PPL101",
            currentOdorCue: .amber,
            learnedValence: 0.42,
            memoryConfidence: 0.61,
            activeKenyonCellCount: 62,
            rewardDANActivity: 0.18,
            punishmentDANActivity: 0.02,
            memorySummary: "记得琥珀果香通常带来食物",
            controllerCircuit: "ENG-SELF-PREDICT↔ENG-COUNTERFACTUAL↔ENG-SEMANTIC-SELF↔ENG-OTHER-MODEL→ENG-ACTION-WTA",
            controllerProvenance: "fitted/assumed",
            controllerNeuronCount: 49,
            activeControllerNeuronCount: 17,
            selectedActionNeuron: "ENG-ACT-EXPLORE",
            actionConfidence: 0.31,
            forwardSpeed: 0.024,
            turnRateRadiansPerSecond: 0.18,
            feedingMotorDrive: 0,
            groomingMotorDrive: 0,
            restMotorDrive: 0,
            actionNeuronActivities: [0.22, 0.84, 0.48, 0.31, 0.08, 0.03, 0.45, 0.14, 0.11, 0.28, 0.04, 0],
            wholeCNSDataset: "male-cns:v1.0",
            wholeCNSGraphSHA256: "35c7973b35f4…",
            wholeCNSNodeCount: 165_122,
            wholeCNSEdgeCount: 25_563_197,
            wholeCNSActiveNeuronCount: 276,
            wholeCNSSpikeCount: 152,
            wholeCNSEdgeEventCount: 52_981,
            wholeCNSRealTimeFactor: 2.03,
            wholeCNSSensoryActivity: 0.0024,
            wholeCNSCentralComplexActivity: 0.0042,
            wholeCNSDescendingActivity: 0.0070,
            wholeCNSMotorActivity: 0.0010,
            wholeCNSDopamineLevel: 0.21,
            wholeCNSSerotoninLevel: 0.001,
            wholeCNSOctopamineLevel: 0.006,
            wholeCNSPlasticSynapseSourceCount: 997,
            wholeCNSEventBudgetSaturated: false,
            functionalSelf: FunctionalSelfState(
                individualID: UUID(uuidString: "B2B88132-EE6D-47AC-96F2-F30DF3937D6A")!,
                bodilyCoherence: 0.91,
                agencyScore: 0.84,
                confidence: 0.79,
                sensorReliability: 0.96,
                actionCapability: 0.83,
                predictionError: 0.08,
                causalAttribution: .selfGenerated,
                predictedDisplacement: 0.0024,
                observedDisplacement: 0.0022,
                predictedEnergyDelta: -0.00002,
                observedEnergyDelta: -0.00002,
                episodeRevision: 2,
                episodes: [
                    FunctionalSelfEpisode(
                        tick: 4_208,
                        recordedAt: now,
                        behavior: .exploring,
                        actionNeuron: "ENG-ACT-EXPLORE",
                        attribution: .selfGenerated,
                        predictionError: 0.08,
                        confidence: 0.79,
                        summary: "探索运动与运动副本预测一致"
                    )
                ],
                explanation: "探索运动与运动副本预测一致，当前归因为自身行动"
            ),
            counterfactualSelf: CounterfactualSelfState(
                individualID: UUID(uuidString: "B2B88132-EE6D-47AC-96F2-F30DF3937D6A")!,
                revision: 84,
                candidates: [
                    CounterfactualActionEvaluation(
                        behavior: .exploring,
                        actionNeuron: "ENG-ACT-EXPLORE",
                        predictedDisplacement: 0.045,
                        predictedEnergyCost: 0.018,
                        predictedThreatExposure: 0.08,
                        expectedInformationGain: 0.92,
                        expectedUtility: 0.76,
                        confidence: 0.82
                    ),
                    CounterfactualActionEvaluation(
                        behavior: .walking,
                        actionNeuron: "ENG-ACT-WALK",
                        predictedDisplacement: 0.065,
                        predictedEnergyCost: 0.023,
                        predictedThreatExposure: 0.11,
                        expectedInformationGain: 0.58,
                        expectedUtility: 0.51,
                        confidence: 0.78
                    )
                ],
                selectedBehavior: .exploring,
                selectedActionNeuron: "ENG-ACT-EXPLORE",
                selfHypothesisProbability: 0.86,
                worldHypothesisProbability: 0.14,
                ambiguity: 0.28,
                epistemicDrive: 0.26,
                shouldProbe: false,
                calibrationSampleCount: 64,
                calibrationAccuracy: 0.84,
                meanDecisionConfidence: 0.81,
                brierScore: 0.12,
                calibrationError: 0.03,
                blindExternalEventCount: 7,
                explanation: "比较候选未来后，优先探索环境"
            ),
            semanticSelf: SemanticSelfState(
                individualID: UUID(uuidString: "B2B88132-EE6D-47AC-96F2-F30DF3937D6A")!,
                revision: 19,
                activeGoal: .exploreWorld,
                goalSinceTick: 4_160,
                goalStability: 0.80,
                preferences: SelfPreferenceProfile(
                    exploration: 0.71,
                    caution: 0.45,
                    energyConservation: 0.49,
                    cleanliness: 0.52,
                    socialInterest: 0.56
                ),
                beliefs: [
                    SemanticSelfBelief(
                        key: "motor-control",
                        displayName: "身体控制可靠性",
                        value: 0.91,
                        confidence: 0.88,
                        evidenceCount: 18,
                        summary: "依据行动与后果整合"
                    )
                ],
                consolidationCount: 18,
                narrativeSummary: "长期目标为探索环境；身体控制目前可靠。"
            ),
            socialSelf: SocialSelfState(
                individualID: UUID(uuidString: "B2B88132-EE6D-47AC-96F2-F30DF3937D6A")!,
                revision: 42,
                otherPresent: true,
                trackedOtherID: "OTHER-ALPHA",
                selfOtherSeparation: 0.81,
                otherAgencyProbability: 0.74,
                predictedOtherResponse: 0.68,
                observedOtherMotion: 0.62,
                affiliation: 0.66,
                vigilance: 0.22,
                jointActionProbability: 0.54,
                attribution: .joint,
                socialEpisodeCount: 5,
                explanation: "自身行动与 OTHER-ALPHA 的条件响应共同解释当前变化"
            ),
            positionX: 0.62,
            positionY: 0.18,
            headingRadians: 0.25,
            reason: "环境平静，正在主动探索",
            modelFidelity: .socialSelfCognition
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}
