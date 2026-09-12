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

    public var displayName: String {
        switch self {
        case .bootstrap: "自主状态基础模型"
        case .hybridConnectome: "MaleCNS 视觉回路混合模型"
        case .hybridLearning: "MaleCNS 视觉与学习回路混合模型"
        case .embodiedNeural: "MaleCNS 约束的全动作神经模型"
        case .connectomeConstrained: "MaleCNS 连接组约束模型"
        }
    }
}

public struct FlyStateSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

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
            controllerCircuit: "ENG-SENSORY→ENG-ACTION-WTA→ENG-DESCENDING",
            controllerProvenance: "fitted/assumed",
            controllerNeuronCount: 38,
            activeControllerNeuronCount: 17,
            selectedActionNeuron: "ENG-ACT-EXPLORE",
            actionConfidence: 0.31,
            forwardSpeed: 0.024,
            turnRateRadiansPerSecond: 0.18,
            feedingMotorDrive: 0,
            groomingMotorDrive: 0,
            restMotorDrive: 0,
            actionNeuronActivities: [0.22, 0.84, 0.48, 0.31, 0.08, 0.03, 0.45, 0.14, 0.11, 0.28, 0.04, 0],
            positionX: 0.62,
            positionY: 0.18,
            headingRadians: 0.25,
            reason: "环境平静，正在主动探索",
            modelFidelity: .embodiedNeural
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}
