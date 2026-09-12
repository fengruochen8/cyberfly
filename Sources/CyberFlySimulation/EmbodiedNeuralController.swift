import CyberFlyCore
import Foundation

/// The complete action-selection and descending-motor layer for the desktop fly.
///
/// MaleCNS does not currently provide enough measured dynamics to reconstruct a
/// complete behaving animal. The populations in this controller are therefore
/// explicitly engineering populations (`fitted`/`assumed`). Observed MaleCNS
/// visual and olfactory-learning outputs enter as sensory signals; they are not
/// relabelled as observed action or motor neurons.
public struct EmbodiedNeuralInput: Sendable {
    public var lifeState: FlyLifeState
    public var energy: Double
    public var fatigue: Double
    public var arousal: Double
    public var groomingNeed: Double
    public var stress: Double
    public var curiosity: Double
    public var foodOdor: Double
    public var foodContact: Double
    public var foodBearingRadians: Double?
    public var learnedValence: Double
    public var memoryConfidence: Double
    public var threat: Double
    public var threatBearingRadians: Double?
    public var touch: Double
    public var novelty: Double
    public var contamination: Double
    public var visualTurnBias: Double
    public var headingRadians: Double

    public init(
        lifeState: FlyLifeState = .active,
        energy: Double = 0.78,
        fatigue: Double = 0.18,
        arousal: Double = 0.22,
        groomingNeed: Double = 0.15,
        stress: Double = 0.08,
        curiosity: Double = 0.68,
        foodOdor: Double = 0,
        foodContact: Double = 0,
        foodBearingRadians: Double? = nil,
        learnedValence: Double = 0,
        memoryConfidence: Double = 0,
        threat: Double = 0,
        threatBearingRadians: Double? = nil,
        touch: Double = 0,
        novelty: Double = 0,
        contamination: Double = 0,
        visualTurnBias: Double = 0,
        headingRadians: Double = 0
    ) {
        self.lifeState = lifeState
        self.energy = Self.clamp(energy)
        self.fatigue = Self.clamp(fatigue)
        self.arousal = Self.clamp(arousal)
        self.groomingNeed = Self.clamp(groomingNeed)
        self.stress = Self.clamp(stress)
        self.curiosity = Self.clamp(curiosity)
        self.foodOdor = Self.clamp(foodOdor)
        self.foodContact = Self.clamp(foodContact)
        self.foodBearingRadians = foodBearingRadians
        self.learnedValence = Self.clampSigned(learnedValence)
        self.memoryConfidence = Self.clamp(memoryConfidence)
        self.threat = Self.clamp(threat)
        self.threatBearingRadians = threatBearingRadians
        self.touch = Self.clamp(touch)
        self.novelty = Self.clamp(novelty)
        self.contamination = Self.clamp(contamination)
        self.visualTurnBias = Self.clampSigned(visualTurnBias)
        self.headingRadians = headingRadians
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}

public struct EmbodiedNeuralOutput: Equatable, Sendable {
    public static let circuitID = "ENG-SENSORY→ENG-ACTION-WTA→ENG-DESCENDING"
    public static let provenance = "fitted/assumed"
    public static let totalNeuronCount = 38

    public let behavior: FlyBehavior
    public let selectedActionNeuron: String
    public let actionConfidence: Double
    public let activeNeuronCount: Int
    public let meanActivity: Double
    public let forwardSpeed: Double
    public let turnRateRadiansPerSecond: Double
    public let wingDrive: Double
    public let feedingDrive: Double
    public let groomingDrive: Double
    public let restDrive: Double
    public let actionActivities: [Double]

    public static let silent = EmbodiedNeuralOutput(
        behavior: .idle,
        selectedActionNeuron: EmbodiedNeuralController.actionNeuronID(for: .idle),
        actionConfidence: 0,
        activeNeuronCount: 0,
        meanActivity: 0,
        forwardSpeed: 0,
        turnRateRadiansPerSecond: 0,
        wingDrive: 0,
        feedingDrive: 0,
        groomingDrive: 0,
        restDrive: 0,
        actionActivities: Array(repeating: 0, count: FlyBehavior.allCases.count)
    )
}

/// A stateful rate-neuron network. Neural noise is the only source of stochastic
/// action variation; there are no behavior timers or non-neural action rules.
public struct EmbodiedNeuralController: Sendable {
    public static let circuitID = EmbodiedNeuralOutput.circuitID
    public static let provenance = EmbodiedNeuralOutput.provenance
    public static let totalNeuronCount = EmbodiedNeuralOutput.totalNeuronCount

    private var actionMembranes = Array(repeating: 0.0, count: FlyBehavior.allCases.count)
    private var forwardSpeed = 0.0
    private var turnRate = 0.0
    private var wingDrive = 0.0
    private var feedingDrive = 0.0
    private var groomingDrive = 0.0
    private var restDrive = 0.0
    private var isSilenced: Bool

    public init(isSilenced: Bool = false) {
        self.isSilenced = isSilenced
    }

    public mutating func setSilenced(_ silenced: Bool) {
        isSilenced = silenced
        if silenced {
            actionMembranes = Array(repeating: 0, count: FlyBehavior.allCases.count)
            forwardSpeed = 0
            turnRate = 0
            wingDrive = 0
            feedingDrive = 0
            groomingDrive = 0
            restDrive = 0
        }
    }

    public mutating func restore(
        actionActivities: [Double]?,
        forwardSpeed: Double?,
        turnRateRadiansPerSecond: Double?,
        wingDrive: Double?,
        feedingDrive: Double?,
        groomingDrive: Double?,
        restDrive: Double?
    ) {
        if let actionActivities,
           actionActivities.count == FlyBehavior.allCases.count {
            actionMembranes = actionActivities.map(Self.inverseSigmoid)
        }
        self.forwardSpeed = max(forwardSpeed ?? 0, 0)
        turnRate = Self.clamp(turnRateRadiansPerSecond ?? 0, minimum: -4, maximum: 4)
        self.wingDrive = Self.clamp(wingDrive ?? 0)
        self.feedingDrive = Self.clamp(feedingDrive ?? 0)
        self.groomingDrive = Self.clamp(groomingDrive ?? 0)
        self.restDrive = Self.clamp(restDrive ?? 0)
    }

    public mutating func step(
        input: EmbodiedNeuralInput,
        deltaTime rawDeltaTime: TimeInterval,
        neuralNoise: Double
    ) -> EmbodiedNeuralOutput {
        guard !isSilenced else { return .silent }

        let deltaTime = min(max(rawDeltaTime, 0.001), 1)
        let behaviors = FlyBehavior.allCases
        let previousActivities = actionMembranes.map(Self.sigmoid)
        let strongestPrevious = previousActivities.max() ?? 0
        let signedNoise = Self.clampSigned(neuralNoise)

        for (index, behavior) in behaviors.enumerated() {
            let sensoryDrive = drive(for: behavior, input: input)
            let recurrentDrive = previousActivities[index] * 0.34
            let lateralInhibition = max(strongestPrevious - previousActivities[index], 0) * 0.42
            let noisePhase = sin(Double(index + 1) * 2.399963 + signedNoise * 3.1)
            let noiseDrive = noisePhase * 0.045
            let target = sensoryDrive + recurrentDrive - lateralInhibition + noiseDrive
            let integrationRate = min(deltaTime * 9, 1)
            actionMembranes[index] += (target - actionMembranes[index]) * integrationRate
        }

        let activities = actionMembranes.map(Self.sigmoid)
        let winnerIndex = activities.indices.max { activities[$0] < activities[$1] } ?? 0
        let behavior = behaviors[winnerIndex]
        let winnerActivity = activities[winnerIndex]
        let sorted = activities.sorted(by: >)
        let confidence = Self.clamp((sorted.first ?? 0) - (sorted.dropFirst().first ?? 0))

        let motorTargets = descendingMotorTargets(
            behavior: behavior,
            actionActivity: winnerActivity,
            input: input,
            neuralNoise: signedNoise
        )
        let motorRate = min(deltaTime * 12, 1)
        forwardSpeed += (motorTargets.forwardSpeed - forwardSpeed) * motorRate
        turnRate += (motorTargets.turnRate - turnRate) * motorRate
        wingDrive += (motorTargets.wingDrive - wingDrive) * motorRate
        feedingDrive += (motorTargets.feedingDrive - feedingDrive) * motorRate
        groomingDrive += (motorTargets.groomingDrive - groomingDrive) * motorRate
        restDrive += (motorTargets.restDrive - restDrive) * motorRate

        let sensoryActivities = sensoryActivityVector(input)
        let motorActivities = [
            min(forwardSpeed / 0.13, 1),
            min(abs(turnRate) / 4, 1),
            wingDrive,
            feedingDrive,
            groomingDrive,
            restDrive
        ]
        let competitionInterneurons = [strongestPrevious, abs(signedNoise) * 0.2]
        let allActivities = sensoryActivities + activities + motorActivities + competitionInterneurons
        let activeCount = allActivities.filter { $0 >= 0.12 }.count
        let meanActivity = allActivities.reduce(0, +) / Double(max(allActivities.count, 1))

        return EmbodiedNeuralOutput(
            behavior: behavior,
            selectedActionNeuron: Self.actionNeuronID(for: behavior),
            actionConfidence: confidence,
            activeNeuronCount: activeCount,
            meanActivity: Self.clamp(meanActivity),
            forwardSpeed: max(forwardSpeed, 0),
            turnRateRadiansPerSecond: turnRate,
            wingDrive: Self.clamp(wingDrive),
            feedingDrive: Self.clamp(feedingDrive),
            groomingDrive: Self.clamp(groomingDrive),
            restDrive: Self.clamp(restDrive),
            actionActivities: activities
        )
    }

    public static func actionNeuronID(for behavior: FlyBehavior) -> String {
        switch behavior {
        case .idle: "ENG-ACT-IDLE"
        case .exploring: "ENG-ACT-EXPLORE"
        case .walking: "ENG-ACT-WALK"
        case .foraging: "ENG-ACT-FORAGE"
        case .avoidingOdor: "ENG-ACT-ODOR-AVOID"
        case .feeding: "ENG-ACT-FEED"
        case .flying: "ENG-ACT-FLY"
        case .groomingHead: "ENG-ACT-GROOM-HEAD"
        case .groomingWings: "ENG-ACT-GROOM-WINGS"
        case .resting: "ENG-ACT-REST"
        case .startled: "ENG-ACT-ESCAPE"
        case .torpor: "ENG-ACT-TORPOR"
        }
    }

    private func drive(for behavior: FlyBehavior, input: EmbodiedNeuralInput) -> Double {
        guard input.lifeState == .active else {
            return behavior == .torpor ? 8 : -8
        }

        let hunger = 1 - input.energy
        let threat = max(input.threat, input.touch)
        let learnedApproach = max(input.learnedValence, 0) * input.memoryConfidence
        let learnedAvoidance = max(-input.learnedValence, 0) * input.memoryConfidence

        switch behavior {
        case .idle:
            return 0.30 + (1 - input.arousal) * 0.20 + (1 - input.curiosity) * 0.10
                - hunger * 0.15 - threat * 1.2
        case .exploring:
            return 0.12 + input.curiosity * 0.90 + input.novelty * 0.48
                - threat * 1.1 - input.fatigue * 0.22
        case .walking:
            return 0.16 + input.curiosity * 0.38 + input.arousal * 0.28
                - threat * 0.65 - input.fatigue * 0.16
        case .foraging:
            return 0.10 + hunger * 0.38
                + hunger * input.foodOdor * (2.35 + learnedApproach * 1.25 - learnedAvoidance * 0.8)
                - threat * 1.0
        case .avoidingOdor:
            return 0.04 + learnedAvoidance * input.foodOdor * 4.2 + input.stress * 0.08
        case .feeding:
            return 0.02 + hunger * input.foodContact * 3.9 + input.foodContact * 0.45
                - threat * 1.5
        case .flying:
            let metabolicInhibition = input.energy < 0.16 || input.fatigue > 0.82 ? 2.5 : 0
            return 0.07 + input.curiosity * input.novelty * 1.25 + input.arousal * 0.32
                - input.fatigue * 0.24 - metabolicInhibition
        case .groomingHead:
            return 0.08 + input.groomingNeed * 1.03 + input.contamination * 0.58
                - threat * 1.15
        case .groomingWings:
            return 0.07 + input.groomingNeed * 0.98 + input.contamination * 0.52
                + input.arousal * 0.18 - threat * 1.15
        case .resting:
            return 0.12 + input.fatigue * 1.48 + hunger * 0.24 + (1 - input.arousal) * 0.10
                - threat * 1.3
        case .startled:
            return 0.02 + threat * 4.4 + input.arousal * threat * 0.5
        case .torpor:
            return -4
        }
    }

    private func descendingMotorTargets(
        behavior: FlyBehavior,
        actionActivity: Double,
        input: EmbodiedNeuralInput,
        neuralNoise: Double
    ) -> (
        forwardSpeed: Double,
        turnRate: Double,
        wingDrive: Double,
        feedingDrive: Double,
        groomingDrive: Double,
        restDrive: Double
    ) {
        let gaitGain: Double
        let wingGain: Double
        let feedGain: Double
        let groomGain: Double
        let restGain: Double

        switch behavior {
        case .startled:
            gaitGain = 1
            wingGain = 0.58
            feedGain = 0
            groomGain = 0
            restGain = 0
        case .flying:
            gaitGain = 0.66
            wingGain = 1
            feedGain = 0
            groomGain = 0
            restGain = 0
        case .walking, .exploring, .foraging, .avoidingOdor:
            gaitGain = 0.22
            wingGain = 0
            feedGain = 0
            groomGain = 0
            restGain = 0
        case .feeding:
            gaitGain = 0
            wingGain = 0
            feedGain = 1
            groomGain = 0
            restGain = 0.12
        case .groomingHead:
            gaitGain = 0
            wingGain = 0
            feedGain = 0
            groomGain = 1
            restGain = 0
        case .groomingWings:
            gaitGain = 0
            wingGain = 0.18
            feedGain = 0
            groomGain = 1
            restGain = 0
        case .resting:
            gaitGain = 0
            wingGain = 0
            feedGain = 0
            groomGain = 0
            restGain = 1
        case .torpor:
            gaitGain = 0
            wingGain = 0
            // A contact-evoked proboscis reflex can restore energy without
            // bypassing the neural motor layer.
            feedGain = 0.32
            groomGain = 0
            restGain = 1
        case .idle:
            gaitGain = 0
            wingGain = input.arousal > 0.7 ? 0.10 : 0.02
            feedGain = 0
            groomGain = 0
            restGain = 0.35
        }

        let directionDrive: Double
        switch behavior {
        case .foraging:
            directionDrive = relativeTurn(
                from: input.headingRadians,
                toward: input.foodBearingRadians
            ) * 3.2
        case .avoidingOdor:
            directionDrive = relativeTurn(
                from: input.headingRadians,
                toward: input.foodBearingRadians.map { Self.normalizedAngle($0 + .pi) }
            ) * 3.6
        case .startled:
            directionDrive = relativeTurn(
                from: input.headingRadians,
                toward: input.threatBearingRadians.map { Self.normalizedAngle($0 + .pi) }
            ) * 4.0
        case .walking, .exploring, .flying:
            directionDrive = input.visualTurnBias * 1.6 + neuralNoise * 0.82
        case .idle, .feeding, .groomingHead, .groomingWings, .resting, .torpor:
            directionDrive = 0
        }

        return (
            forwardSpeed: 0.13 * gaitGain * actionActivity,
            turnRate: Self.clamp(directionDrive * actionActivity, minimum: -4, maximum: 4),
            wingDrive: Self.clamp(wingGain * actionActivity),
            feedingDrive: Self.clamp(feedGain * actionActivity * input.foodContact),
            groomingDrive: Self.clamp(groomGain * actionActivity),
            restDrive: Self.clamp(restGain * actionActivity)
        )
    }

    private func sensoryActivityVector(_ input: EmbodiedNeuralInput) -> [Double] {
        [
            1 - input.energy,
            input.fatigue,
            input.arousal,
            input.groomingNeed,
            input.stress,
            input.curiosity,
            input.foodOdor,
            input.foodContact,
            max(input.learnedValence, 0) * input.memoryConfidence,
            max(-input.learnedValence, 0) * input.memoryConfidence,
            max(input.threat, input.touch),
            input.novelty,
            input.contamination,
            abs(input.visualTurnBias),
            input.lifeState == .active ? 0 : 1,
            input.foodBearingRadians == nil ? 0 : 1,
            input.threatBearingRadians == nil ? 0 : 1,
            input.energy
        ]
    }

    private func relativeTurn(from heading: Double, toward target: Double?) -> Double {
        guard let target else { return 0 }
        return Self.normalizedAngle(target - heading) / .pi
    }

    private static func sigmoid(_ membrane: Double) -> Double {
        1 / (1 + exp(-(membrane - 0.46) * 3.2))
    }

    private static func inverseSigmoid(_ activity: Double) -> Double {
        let bounded = min(max(activity, 0.000_001), 0.999_999)
        return log(bounded / (1 - bounded)) / 3.2 + 0.46
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }

    private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        var result = angle
        while result > .pi { result -= .pi * 2 }
        while result < -.pi { result += .pi * 2 }
        return result
    }
}
