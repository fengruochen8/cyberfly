import CyberFlyCore
import Foundation

public final class FlySimulation: @unchecked Sendable {
    public let individualID: UUID

    private let configuration: SimulationConfiguration
    private var random: DeterministicRandom
    private var tick: UInt64 = 0
    private var lifeState: FlyLifeState = .active
    private var behavior: FlyBehavior = .idle
    private var energy: Double
    private var fatigue: Double = 0.18
    private var arousal: Double = 0.22
    private var groomingNeed: Double = 0.15
    private var stress: Double = 0.08
    private var curiosity: Double = 0.68
    private var valence: Double = 0.58
    private var wellbeing: Double = 0.66
    private var wingActivity: Double = 0
    private var neuralActivity: Double = 0.22
    private var visualCircuit = MaleCNSVisualCircuit()
    private var latestCircuitOutput = MaleCNSCircuitOutput.silent
    private var learningCircuit: MaleCNSLearningCircuit
    private var latestLearningOutput = MaleCNSLearningOutput.silent
    private var embodiedController: EmbodiedNeuralController
    private var latestEmbodiedOutput = EmbodiedNeuralOutput.silent
    private var positionX: Double = 0.52
    private var positionY: Double = 0.12
    private var headingRadians: Double = 0

    public init(
        individualID: UUID = UUID(),
        seed: UInt64 = 0xC0FFEE,
        initialEnergy: Double = 0.78,
        learningMemory: MaleCNSLearningMemory? = nil,
        neuralControllerEnabled: Bool = true,
        configuration: SimulationConfiguration = .standard
    ) {
        self.individualID = individualID
        self.random = DeterministicRandom(seed: seed)
        self.energy = Self.clamp(initialEnergy)
        self.learningCircuit = MaleCNSLearningCircuit(memory: learningMemory)
        self.embodiedController = EmbodiedNeuralController(isSilenced: !neuralControllerEnabled)
        self.configuration = configuration
    }

    public convenience init(
        restoring snapshot: FlyStateSnapshot,
        seed: UInt64? = nil,
        learningMemory: MaleCNSLearningMemory? = nil,
        configuration: SimulationConfiguration = .standard
    ) {
        self.init(
            individualID: snapshot.individualID,
            seed: seed ?? Self.restorationSeed(for: snapshot),
            initialEnergy: snapshot.energy,
            learningMemory: learningMemory,
            neuralControllerEnabled: true,
            configuration: configuration
        )
        tick = snapshot.tick
        lifeState = snapshot.lifeState
        behavior = snapshot.behavior
        fatigue = snapshot.fatigue
        arousal = snapshot.arousal
        groomingNeed = snapshot.groomingNeed
        stress = Self.clamp(max(0, 0.56 - snapshot.valence) / 0.58)
        curiosity = snapshot.curiosity
        valence = snapshot.valence
        wellbeing = snapshot.wellbeing
        wingActivity = snapshot.wingActivity
        neuralActivity = snapshot.neuralActivity
        positionX = snapshot.positionX
        positionY = snapshot.positionY
        headingRadians = snapshot.headingRadians
        embodiedController.restore(
            actionActivities: snapshot.actionNeuronActivities,
            forwardSpeed: snapshot.forwardSpeed,
            turnRateRadiansPerSecond: snapshot.turnRateRadiansPerSecond,
            wingDrive: snapshot.wingActivity,
            feedingDrive: snapshot.feedingMotorDrive,
            groomingDrive: snapshot.groomingMotorDrive,
            restDrive: snapshot.restMotorDrive
        )
        latestEmbodiedOutput = EmbodiedNeuralOutput(
            behavior: snapshot.behavior,
            selectedActionNeuron: snapshot.selectedActionNeuron
                ?? EmbodiedNeuralController.actionNeuronID(for: snapshot.behavior),
            actionConfidence: snapshot.actionConfidence ?? 0,
            activeNeuronCount: snapshot.activeControllerNeuronCount ?? 0,
            meanActivity: snapshot.neuralActivity,
            forwardSpeed: snapshot.forwardSpeed ?? 0,
            turnRateRadiansPerSecond: snapshot.turnRateRadiansPerSecond ?? 0,
            wingDrive: snapshot.wingActivity,
            feedingDrive: snapshot.feedingMotorDrive ?? 0,
            groomingDrive: snapshot.groomingMotorDrive ?? 0,
            restDrive: snapshot.restMotorDrive ?? 0,
            actionActivities: snapshot.actionNeuronActivities
                ?? Array(repeating: 0, count: FlyBehavior.allCases.count)
        )
    }

    @discardableResult
    public func step(
        deltaTime rawDeltaTime: TimeInterval,
        stimulus: FlyStimulus = .quiet,
        now: Date = Date()
    ) -> FlyStateSnapshot {
        let deltaTime = min(max(rawDeltaTime, 0.001), 1)
        tick &+= 1

        updateConnectome(deltaTime: deltaTime, stimulus: stimulus)
        updateLearningCircuit(deltaTime: deltaTime, stimulus: stimulus)
        updateBodyState(deltaTime: deltaTime, stimulus: stimulus)
        updateLifeState(stimulus: stimulus)
        updateAffect(deltaTime: deltaTime, stimulus: stimulus)
        updateEmbodiedController(deltaTime: deltaTime, stimulus: stimulus)
        updateMotion(deltaTime: deltaTime)
        updateNeuralActivity(deltaTime: deltaTime)

        return makeSnapshot(now: now, stimulus: stimulus)
    }

    public func revive() {
        guard lifeState != .active else { return }
        lifeState = .active
        energy = max(energy, 0.28)
        fatigue = min(fatigue, 0.48)
        stress = min(stress, 0.35)
        embodiedController.setSilenced(false)
    }

    public func addContamination(_ amount: Double) {
        groomingNeed = Self.clamp(groomingNeed + max(amount, 0))
    }

    public var learningMemoryRevision: UInt64 {
        learningCircuit.memoryRevision
    }

    public func exportLearningMemory(now: Date = Date()) -> MaleCNSLearningMemory {
        learningCircuit.exportMemory(now: now)
    }

    private func updateBodyState(deltaTime: Double, stimulus: FlyStimulus) {
        let walkingFraction = Self.clamp(latestEmbodiedOutput.forwardSpeed / 0.13)
        let flightFraction = latestEmbodiedOutput.wingDrive
        let groomingFraction = latestEmbodiedOutput.groomingDrive
        let activityMultiplier = 1
            + walkingFraction * (configuration.walkingEnergyMultiplier - 1)
            + flightFraction * (configuration.flightEnergyMultiplier - 1)
            + groomingFraction * 0.6

        energy -= configuration.basalEnergyCostPerSecond * activityMultiplier * deltaTime
        energy += configuration.feedingEnergyPerSecond
            * latestEmbodiedOutput.feedingDrive
            * stimulus.foodContact
            * deltaTime
        energy = Self.clamp(energy)

        fatigue += configuration.fatigueGainPerSecond
            * (walkingFraction + flightFraction * 4 + groomingFraction * 0.6)
            * deltaTime
        fatigue -= configuration.restRecoveryPerSecond
            * latestEmbodiedOutput.restDrive
            * deltaTime
        fatigue = Self.clamp(fatigue)

        groomingNeed += configuration.naturalContaminationPerSecond * deltaTime
        groomingNeed += stimulus.contamination * 0.07 * deltaTime
        groomingNeed -= configuration.groomingRecoveryPerSecond
            * latestEmbodiedOutput.groomingDrive
            * deltaTime
        groomingNeed = Self.clamp(groomingNeed)
    }

    private func updateLifeState(stimulus: FlyStimulus) {
        if lifeState == .dead { return }

        if energy <= 0.0001 {
            if configuration.permanentDeath {
                lifeState = .dead
            } else {
                lifeState = .torpor
                energy = 0.001
            }
        } else if energy <= configuration.torporEnergyThreshold {
            lifeState = .torpor
        } else if lifeState == .torpor,
                  stimulus.foodContact > 0.8,
                  energy > configuration.torporEnergyThreshold * 1.5 {
            lifeState = .active
        }
    }

    private func updateEmbodiedController(deltaTime: Double, stimulus: FlyStimulus) {
        latestEmbodiedOutput = embodiedController.step(
            input: EmbodiedNeuralInput(
                lifeState: lifeState,
                energy: energy,
                fatigue: fatigue,
                arousal: arousal,
                groomingNeed: groomingNeed,
                stress: stress,
                curiosity: curiosity,
                foodOdor: stimulus.foodOdor,
                foodContact: stimulus.foodContact,
                foodBearingRadians: stimulus.foodBearingRadians,
                learnedValence: latestLearningOutput.currentLearnedValence,
                memoryConfidence: latestLearningOutput.currentMemoryConfidence,
                threat: stimulus.threat,
                threatBearingRadians: stimulus.threatBearingRadians,
                touch: stimulus.touch,
                novelty: stimulus.novelty,
                contamination: stimulus.contamination,
                visualTurnBias: latestCircuitOutput.turnBias,
                headingRadians: headingRadians
            ),
            deltaTime: deltaTime,
            neuralNoise: random.nextSigned()
        )
        behavior = latestEmbodiedOutput.behavior
        wingActivity = latestEmbodiedOutput.wingDrive
    }

    private func updateMotion(deltaTime: Double) {
        headingRadians = Self.normalizedAngle(
            headingRadians + latestEmbodiedOutput.turnRateRadiansPerSecond * deltaTime
        )
        positionX += cos(headingRadians) * latestEmbodiedOutput.forwardSpeed * deltaTime
        positionY += sin(headingRadians) * latestEmbodiedOutput.forwardSpeed * deltaTime

        if positionX < 0.04 || positionX > 0.96 {
            headingRadians = Self.normalizedAngle(.pi - headingRadians)
            positionX = min(max(positionX, 0.04), 0.96)
        }
        if positionY < 0.05 || positionY > 0.93 {
            headingRadians = Self.normalizedAngle(-headingRadians)
            positionY = min(max(positionY, 0.05), 0.93)
        }
    }

    private func updateConnectome(deltaTime: Double, stimulus: FlyStimulus) {
        let visualDrive = Self.clamp(max(stimulus.novelty, stimulus.threat * 0.9))
        let bearing = stimulus.visualMotionBearingRadians ?? stimulus.threatBearingRadians
        let lateral: Double
        if let bearing {
            lateral = sin(Self.normalizedAngle(bearing - headingRadians))
        } else {
            lateral = 0
        }
        let leftMotion = visualDrive * Self.clamp(0.62 + lateral * 0.38)
        let rightMotion = visualDrive * Self.clamp(0.62 - lateral * 0.38)
        latestCircuitOutput = visualCircuit.step(
            leftVisualMotion: leftMotion,
            rightVisualMotion: rightMotion,
            deltaTime: deltaTime
        )
    }

    private func updateLearningCircuit(deltaTime: Double, stimulus: FlyStimulus) {
        let reward = latestEmbodiedOutput.feedingDrive * stimulus.foodContact
        let punishment = max(stimulus.threat, stimulus.touch)
        latestLearningOutput = learningCircuit.step(
            amberOdor: stimulus.amberOdor,
            berryOdor: stimulus.berryOdor,
            rewardSignal: reward,
            punishmentSignal: punishment,
            deltaTime: deltaTime
        )
    }

    private func updateAffect(deltaTime: Double, stimulus: FlyStimulus) {
        let immediateThreat = max(stimulus.threat, stimulus.touch)
        let arousalTarget = Self.clamp(0.12 + immediateThreat * 0.86 + stimulus.novelty * 0.48)
        arousal = Self.approach(arousal, arousalTarget, rate: 1.7 * deltaTime)

        let stressTarget = Self.clamp(immediateThreat * 0.95 + fatigue * 0.18)
        stress = Self.approach(stress, stressTarget, rate: 0.75 * deltaTime)

        curiosity += 0.006 * (1 - stimulus.novelty) * deltaTime
        curiosity -= stimulus.novelty * 0.035 * deltaTime
        curiosity -= immediateThreat * 0.08 * deltaTime
        curiosity -= Self.clamp(latestEmbodiedOutput.forwardSpeed / 0.13) * 0.01 * deltaTime
        curiosity = Self.clamp(curiosity)

        let foodPleasure = latestEmbodiedOutput.feedingDrive * stimulus.foodContact * 0.32
        let valenceTarget = Self.clamp(0.56 + foodPleasure - stress * 0.58 - (1 - energy) * 0.26 - fatigue * 0.13)
        valence = Self.approach(valence, valenceTarget, rate: 0.85 * deltaTime)

        let wellbeingTarget = Self.clamp(
            energy * 0.43
                + (1 - fatigue) * 0.19
                + (1 - stress) * 0.2
                + valence * 0.18
        )
        wellbeing = Self.approach(wellbeing, wellbeingTarget, rate: 0.18 * deltaTime)
    }

    private func updateNeuralActivity(deltaTime: Double) {
        let activityTarget = Self.clamp(
            latestEmbodiedOutput.meanActivity * 0.58
                + min(latestCircuitOutput.meanFiringRateHz / 80, 1) * 0.24
                + Double(latestLearningOutput.activeKenyonCellCount)
                    / Double(max(latestLearningOutput.kenyonCellCount, 1)) * 0.30
                + max(
                    latestLearningOutput.rewardDANActivity,
                    latestLearningOutput.punishmentDANActivity
                ) * 0.18
        )
        neuralActivity = Self.approach(neuralActivity, activityTarget, rate: 2.2 * deltaTime)
    }

    private func makeSnapshot(now: Date, stimulus: FlyStimulus) -> FlyStateSnapshot {
        let hunger = 1 - energy
        let emotion = classifyEmotion(hunger: hunger)
        return FlyStateSnapshot(
            individualID: individualID,
            sampledAt: now,
            tick: tick,
            lifeState: lifeState,
            behavior: behavior,
            emotion: emotion,
            energy: energy,
            hunger: hunger,
            valence: valence,
            wellbeing: wellbeing,
            curiosity: curiosity,
            arousal: arousal,
            fatigue: fatigue,
            groomingNeed: groomingNeed,
            wingActivity: wingActivity,
            neuralActivity: neuralActivity,
            neuralCircuit: latestCircuitOutput.circuitID,
            activeNeuronCount: latestCircuitOutput.activeNeuronCount,
            learningCircuit: latestLearningOutput.circuitID,
            currentOdorCue: latestLearningOutput.currentCue,
            learnedValence: latestLearningOutput.currentCue == nil
                ? latestLearningOutput.strongestMemoryValence
                : latestLearningOutput.currentLearnedValence,
            memoryConfidence: latestLearningOutput.currentCue == nil
                ? latestLearningOutput.strongestMemoryConfidence
                : latestLearningOutput.currentMemoryConfidence,
            activeKenyonCellCount: latestLearningOutput.activeKenyonCellCount,
            rewardDANActivity: latestLearningOutput.rewardDANActivity,
            punishmentDANActivity: latestLearningOutput.punishmentDANActivity,
            memorySummary: latestLearningOutput.memorySummary,
            controllerCircuit: EmbodiedNeuralController.circuitID,
            controllerProvenance: EmbodiedNeuralController.provenance,
            controllerNeuronCount: EmbodiedNeuralController.totalNeuronCount,
            activeControllerNeuronCount: latestEmbodiedOutput.activeNeuronCount,
            selectedActionNeuron: latestEmbodiedOutput.selectedActionNeuron,
            actionConfidence: latestEmbodiedOutput.actionConfidence,
            forwardSpeed: latestEmbodiedOutput.forwardSpeed,
            turnRateRadiansPerSecond: latestEmbodiedOutput.turnRateRadiansPerSecond,
            feedingMotorDrive: latestEmbodiedOutput.feedingDrive,
            groomingMotorDrive: latestEmbodiedOutput.groomingDrive,
            restMotorDrive: latestEmbodiedOutput.restDrive,
            actionNeuronActivities: latestEmbodiedOutput.actionActivities,
            positionX: positionX,
            positionY: positionY,
            headingRadians: headingRadians,
            reason: reason(for: behavior, stimulus: stimulus),
            modelFidelity: .embodiedNeural
        )
    }

    private func classifyEmotion(hunger: Double) -> FlyEmotion {
        if lifeState != .active { return .dormant }
        if stress > 0.66 { return .distressed }
        if hunger > 0.72 { return .hungry }
        if fatigue > 0.76 { return .tired }
        if arousal > 0.67 { return .alert }
        if curiosity > 0.66 { return .curious }
        if valence > 0.68 { return .happy }
        if wellbeing > 0.62 { return .content }
        return .calm
    }

    private func reason(for behavior: FlyBehavior, stimulus: FlyStimulus) -> String {
        let prefix = "\(latestEmbodiedOutput.selectedActionNeuron) 在神经竞争中胜出"
        let explanation: String
        switch behavior {
        case .idle: explanation = "环境平静，下降运动输出接近静息"
        case .exploring: explanation = "好奇输入增强了探索与行走运动神经元"
        case .walking: explanation = "行走动作神经元驱动前进运动神经元"
        case .foraging:
            if latestLearningOutput.currentLearnedValence > 0.06,
               let cue = latestLearningOutput.currentCue {
                explanation = "\(cue.displayName)的趋近记忆与饥饿输入共同驱动寻食"
            } else {
                explanation = stimulus.foodOdor > 0.05
                    ? "食物气味与饥饿输入共同驱动寻食"
                    : "饥饿输入驱动搜索运动"
            }
        case .avoidingOdor:
            if let cue = latestLearningOutput.currentCue {
                explanation = "PPL101 形成的\(cue.displayName)回避记忆驱动反向转向"
            } else {
                explanation = "回避记忆驱动反向转向神经元"
            }
        case .feeding: explanation = "食物接触与饥饿输入激活进食运动门控"
        case .flying: explanation = "新奇与警觉输入激活飞行和振翅运动神经元"
        case .groomingHead: explanation = "污染与梳理需求输入激活头部梳理模式"
        case .groomingWings: explanation = "污染与梳理需求输入激活翅膀梳理模式"
        case .resting: explanation = "疲劳输入激活休息并抑制下降运动"
        case .startled: explanation = "触觉或威胁输入激活逃逸运动神经元"
        case .torpor: explanation = "低能量状态激活休眠神经元并抑制全部运动"
        }
        return "\(prefix)：\(explanation)"
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func approach(_ value: Double, _ target: Double, rate: Double) -> Double {
        value + (target - value) * min(max(rate, 0), 1)
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        var result = angle
        while result > .pi { result -= .pi * 2 }
        while result < -.pi { result += .pi * 2 }
        return result
    }

    private static func restorationSeed(for snapshot: FlyStateSnapshot) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in snapshot.individualID.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash ^ snapshot.tick
    }
}
