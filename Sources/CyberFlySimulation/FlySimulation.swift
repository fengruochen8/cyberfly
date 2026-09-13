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
    private var functionalSelfModel: FunctionalSelfModel
    private var developmentalSelfModel: DevelopmentalSelfModel
    private var latestCognitiveGuidance = CognitiveActionGuidance.neutral
    private let fullCNSRuntime: FullCNSRuntime?
    private var latestFullCNSMetrics: FullCNSRuntimeMetrics?
    private let modelFidelity: ModelFidelity
    private var positionX: Double = 0.52
    private var positionY: Double = 0.12
    private var headingRadians: Double = 0
    private var pendingExternalDisplacementX = 0.0
    private var pendingExternalDisplacementY = 0.0
    private var pendingExternalHeadingDelta = 0.0
    private var pendingExternalIsRevealed = true
    private var appliedExternalDisplacementX = 0.0
    private var appliedExternalDisplacementY = 0.0
    private var appliedExternalHeadingDelta = 0.0
    private var appliedExternalIsRevealed = true
    private var motorForwardScale = 1.0
    private var motorTurnScale = 1.0

    public init(
        individualID: UUID = UUID(),
        seed: UInt64 = 0xC0FFEE,
        initialEnergy: Double = 0.78,
        learningMemory: MaleCNSLearningMemory? = nil,
        neuralControllerEnabled: Bool = true,
        functionalSelfEnabled: Bool = true,
        functionalSelfState: FunctionalSelfState? = nil,
        counterfactualSelfEnabled: Bool = true,
        semanticSelfEnabled: Bool = true,
        socialSelfEnabled: Bool = true,
        counterfactualSelfState: CounterfactualSelfState? = nil,
        semanticSelfState: SemanticSelfState? = nil,
        socialSelfState: SocialSelfState? = nil,
        fullCNSRuntime: FullCNSRuntime? = nil,
        configuration: SimulationConfiguration = .standard
    ) {
        self.individualID = individualID
        self.random = DeterministicRandom(seed: seed)
        self.energy = Self.clamp(initialEnergy)
        self.learningCircuit = MaleCNSLearningCircuit(
            individualID: individualID,
            memory: learningMemory
        )
        self.embodiedController = EmbodiedNeuralController(isSilenced: !neuralControllerEnabled)
        self.functionalSelfModel = FunctionalSelfModel(
            individualID: individualID,
            enabled: functionalSelfEnabled,
            restoring: functionalSelfState
        )
        self.developmentalSelfModel = DevelopmentalSelfModel(
            individualID: individualID,
            counterfactualEnabled: functionalSelfEnabled && counterfactualSelfEnabled,
            semanticEnabled: functionalSelfEnabled && semanticSelfEnabled,
            socialEnabled: functionalSelfEnabled && socialSelfEnabled,
            restoringCounterfactual: counterfactualSelfState,
            restoringSemantic: semanticSelfState,
            restoringSocial: socialSelfState
        )
        self.fullCNSRuntime = fullCNSRuntime
        self.latestFullCNSMetrics = fullCNSRuntime.map {
            FullCNSRuntimeMetrics.idle(graph: $0.graph)
        }
        if !functionalSelfEnabled {
            self.modelFidelity = fullCNSRuntime == nil
                ? .embodiedNeural : .wholeCNSDigitalFly
        } else if socialSelfEnabled {
            self.modelFidelity = .socialSelfCognition
        } else if semanticSelfEnabled {
            self.modelFidelity = .semanticSelfCognition
        } else if counterfactualSelfEnabled {
            self.modelFidelity = .counterfactualSelfCognition
        } else {
            self.modelFidelity = .functionalSelfCognition
        }
        self.configuration = configuration
    }

    public convenience init(
        restoring snapshot: FlyStateSnapshot,
        seed: UInt64? = nil,
        learningMemory: MaleCNSLearningMemory? = nil,
        fullCNSRuntime: FullCNSRuntime? = nil,
        configuration: SimulationConfiguration = .standard
    ) {
        self.init(
            individualID: snapshot.individualID,
            seed: seed ?? Self.restorationSeed(for: snapshot),
            initialEnergy: snapshot.energy,
            learningMemory: learningMemory,
            neuralControllerEnabled: true,
            functionalSelfEnabled: true,
            functionalSelfState: snapshot.functionalSelf,
            counterfactualSelfEnabled: true,
            semanticSelfEnabled: true,
            socialSelfEnabled: true,
            counterfactualSelfState: snapshot.counterfactualSelf,
            semanticSelfState: snapshot.semanticSelf,
            socialSelfState: snapshot.socialSelf,
            fullCNSRuntime: fullCNSRuntime,
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
        readLearningCircuit(stimulus: stimulus)
        updateFullCNS(deltaTime: deltaTime, stimulus: stimulus)
        latestCognitiveGuidance = developmentalSelfModel.prepare(
            body: currentBodyObservation(),
            functionalSelf: functionalSelfModel.state,
            stimulus: stimulus,
            curiosity: curiosity,
            arousal: arousal,
            tick: tick
        )
        updateEmbodiedController(deltaTime: deltaTime, stimulus: stimulus)
        let bodyBeforeAction = currentBodyObservation()
        let expectedDeltas = predictedBodyDeltas(
            deltaTime: deltaTime,
            stimulus: stimulus
        )
        let selfAction = currentSelfActionCommand()
        let selfPrediction = functionalSelfModel.predict(
            action: selfAction,
            body: bodyBeforeAction,
            deltaTime: deltaTime,
            expectedEnergyDelta: expectedDeltas.energy,
            expectedFatigueDelta: expectedDeltas.fatigue,
            expectedGroomingDelta: expectedDeltas.grooming
        )
        updateBodyState(deltaTime: deltaTime, stimulus: stimulus)
        updateLifeState(stimulus: stimulus)
        updateAffect(deltaTime: deltaTime, stimulus: stimulus)
        updateLearningCircuit(deltaTime: deltaTime, stimulus: stimulus)
        updateMotion(deltaTime: deltaTime)
        updateFunctionalSelf(
            prediction: selfPrediction,
            before: bodyBeforeAction,
            action: selfAction,
            stimulus: stimulus,
            now: now
        )
        updateDevelopmentalSelf(
            before: bodyBeforeAction,
            action: selfAction,
            stimulus: stimulus
        )
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

    public func applyExternalDisplacement(
        deltaX: Double,
        deltaY: Double,
        headingDelta: Double = 0,
        revealToSelfModel: Bool = true
    ) {
        pendingExternalDisplacementX += min(max(deltaX, -0.5), 0.5)
        pendingExternalDisplacementY += min(max(deltaY, -0.5), 0.5)
        pendingExternalHeadingDelta += min(max(headingDelta, -.pi), .pi)
        pendingExternalIsRevealed = revealToSelfModel
    }

    public func setMotorControlTransform(
        forwardScale: Double = 1,
        turnScale: Double = 1
    ) {
        motorForwardScale = min(max(forwardScale, 0), 2)
        motorTurnScale = min(max(turnScale, -2), 2)
    }

    public var functionalSelfState: FunctionalSelfState {
        functionalSelfModel.state
    }

    public var counterfactualSelfState: CounterfactualSelfState {
        developmentalSelfModel.counterfactual
    }

    public var semanticSelfState: SemanticSelfState {
        developmentalSelfModel.semantic
    }

    public var socialSelfState: SocialSelfState {
        developmentalSelfModel.social
    }

    public var learningMemoryRevision: UInt64 {
        learningCircuit.memoryRevision
    }

    public func exportLearningMemory(now: Date = Date()) -> MaleCNSLearningMemory {
        learningCircuit.exportMemory(now: now)
    }

    public func exportFullCNSPersistentState(
        now: Date = Date()
    ) -> FullCNSPersistentState? {
        fullCNSRuntime?.exportPersistentState(individualID: individualID, now: now)
    }

    public var fullCNSManifest: FullCNSManifest? {
        fullCNSRuntime?.graph.manifest
    }

    public func inspectFullCNSNeurons(
        matching query: FullCNSNeuronQuery
    ) -> [FullCNSNeuronObservation] {
        fullCNSRuntime?.inspectNeurons(matching: query) ?? []
    }

    public func inspectFullCNSNeuron(
        bodyID: UInt64
    ) -> FullCNSNeuronObservation? {
        fullCNSRuntime?.inspectNeuron(bodyID: bodyID)
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
        let fullCNSDescendingDrive = Self.clamp(
            (latestFullCNSMetrics?.descendingActivity ?? 0) * 24
        )
        let fullCNSMotorDrive = Self.clamp(
            (latestFullCNSMetrics?.motorActivity ?? 0) * 36
        )
        let fullCNSArousal = Self.clamp(
            (latestFullCNSMetrics?.centralComplexActivity ?? 0) * 20
                + (latestFullCNSMetrics?.octopamineLevel ?? 0) * 0.65
        )
        let wholeCNSTurnBias = latestFullCNSMetrics?.turnBias ?? 0
        let combinedVisualTurnBias = fullCNSRuntime == nil
            ? latestCircuitOutput.turnBias
            : Self.clampSigned(latestCircuitOutput.turnBias * 0.55 + wholeCNSTurnBias * 0.45)
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
                visualTurnBias: combinedVisualTurnBias,
                wholeCNSDescendingDrive: fullCNSDescendingDrive,
                wholeCNSMotorDrive: fullCNSMotorDrive,
                wholeCNSArousal: fullCNSArousal,
                selfModelConfidence: functionalSelfModel.state.confidence,
                selfModelUncertainty: functionalSelfModel.state.uncertainty,
                selfPredictionError: functionalSelfModel.state.predictionError,
                plannedBehavior: latestCognitiveGuidance.preferredBehavior,
                planningConfidence: latestCognitiveGuidance.planningConfidence,
                epistemicDrive: latestCognitiveGuidance.epistemicDrive,
                socialApproachDrive: latestCognitiveGuidance.socialApproachDrive,
                socialAvoidanceDrive: latestCognitiveGuidance.socialAvoidanceDrive,
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
            headingRadians
                + latestEmbodiedOutput.turnRateRadiansPerSecond * motorTurnScale * deltaTime
        )
        positionX += cos(headingRadians)
            * latestEmbodiedOutput.forwardSpeed * motorForwardScale * deltaTime
        positionY += sin(headingRadians)
            * latestEmbodiedOutput.forwardSpeed * motorForwardScale * deltaTime

        appliedExternalDisplacementX = pendingExternalDisplacementX
        appliedExternalDisplacementY = pendingExternalDisplacementY
        appliedExternalHeadingDelta = pendingExternalHeadingDelta
        appliedExternalIsRevealed = pendingExternalIsRevealed
        positionX += appliedExternalDisplacementX
        positionY += appliedExternalDisplacementY
        headingRadians = Self.normalizedAngle(
            headingRadians + appliedExternalHeadingDelta
        )
        pendingExternalDisplacementX = 0
        pendingExternalDisplacementY = 0
        pendingExternalHeadingDelta = 0
        pendingExternalIsRevealed = true

        if positionX < 0.04 || positionX > 0.96 {
            headingRadians = Self.normalizedAngle(.pi - headingRadians)
            positionX = min(max(positionX, 0.04), 0.96)
        }
        if positionY < 0.05 || positionY > 0.93 {
            headingRadians = Self.normalizedAngle(-headingRadians)
            positionY = min(max(positionY, 0.05), 0.93)
        }
    }

    private func currentBodyObservation() -> SelfBodyObservation {
        SelfBodyObservation(
            positionX: positionX,
            positionY: positionY,
            headingRadians: headingRadians,
            energy: energy,
            fatigue: fatigue,
            groomingNeed: groomingNeed,
            lifeState: lifeState
        )
    }

    private func currentSelfActionCommand() -> SelfActionCommand {
        SelfActionCommand(
            behavior: latestEmbodiedOutput.behavior,
            actionNeuron: latestEmbodiedOutput.selectedActionNeuron,
            actionConfidence: latestEmbodiedOutput.actionConfidence,
            forwardSpeed: latestEmbodiedOutput.forwardSpeed,
            turnRateRadiansPerSecond: latestEmbodiedOutput.turnRateRadiansPerSecond,
            wingDrive: latestEmbodiedOutput.wingDrive,
            feedingDrive: latestEmbodiedOutput.feedingDrive,
            groomingDrive: latestEmbodiedOutput.groomingDrive,
            restDrive: latestEmbodiedOutput.restDrive
        )
    }

    private func predictedBodyDeltas(
        deltaTime: Double,
        stimulus: FlyStimulus
    ) -> (energy: Double, fatigue: Double, grooming: Double) {
        let walkingFraction = Self.clamp(latestEmbodiedOutput.forwardSpeed / 0.13)
        let flightFraction = latestEmbodiedOutput.wingDrive
        let groomingFraction = latestEmbodiedOutput.groomingDrive
        let activityMultiplier = 1
            + walkingFraction * (configuration.walkingEnergyMultiplier - 1)
            + flightFraction * (configuration.flightEnergyMultiplier - 1)
            + groomingFraction * 0.6
        let energyDelta = (
            -configuration.basalEnergyCostPerSecond * activityMultiplier
                + configuration.feedingEnergyPerSecond
                    * latestEmbodiedOutput.feedingDrive * stimulus.foodContact
        ) * deltaTime
        let fatigueDelta = (
            configuration.fatigueGainPerSecond
                * (walkingFraction + flightFraction * 4 + groomingFraction * 0.6)
                - configuration.restRecoveryPerSecond * latestEmbodiedOutput.restDrive
        ) * deltaTime
        let groomingDelta = (
            configuration.naturalContaminationPerSecond
                + stimulus.contamination * 0.07
                - configuration.groomingRecoveryPerSecond
                    * latestEmbodiedOutput.groomingDrive
        ) * deltaTime
        return (energyDelta, fatigueDelta, groomingDelta)
    }

    private func updateFunctionalSelf(
        prediction: SelfActionPrediction,
        before: SelfBodyObservation,
        action: SelfActionCommand,
        stimulus: FlyStimulus,
        now: Date
    ) {
        _ = functionalSelfModel.observe(
            prediction: prediction,
            before: before,
            after: currentBodyObservation(),
            action: action,
            external: SelfExternalEvidence(
                touch: stimulus.touch,
                threat: stimulus.threat,
                contamination: stimulus.contamination,
                sensorReliability: stimulus.sensorReliability,
                visualMotion: max(stimulus.novelty, stimulus.threat),
                memoryConfidence: latestLearningOutput.currentMemoryConfidence,
                displacementX: appliedExternalIsRevealed ? appliedExternalDisplacementX : 0,
                displacementY: appliedExternalIsRevealed ? appliedExternalDisplacementY : 0,
                headingDelta: appliedExternalIsRevealed ? appliedExternalHeadingDelta : 0
            ),
            tick: tick,
            now: now
        )
    }

    private func updateDevelopmentalSelf(
        before: SelfBodyObservation,
        action: SelfActionCommand,
        stimulus: FlyStimulus
    ) {
        let externalMagnitude = hypot(
            appliedExternalDisplacementX,
            appliedExternalDisplacementY
        ) + abs(appliedExternalHeadingDelta) * 0.08
        developmentalSelfModel.observe(
            functionalSelf: functionalSelfModel.state,
            selectedAction: action,
            bodyBefore: before,
            bodyAfter: currentBodyObservation(),
            stimulus: stimulus,
            externalCauseForEvaluation: externalMagnitude > 0.008,
            wasBlindExternalEvent: externalMagnitude > 0.008 && !appliedExternalIsRevealed,
            tick: tick
        )
    }

    private func updateConnectome(deltaTime: Double, stimulus: FlyStimulus) {
        let motion = visualMotionInput(stimulus: stimulus)
        latestCircuitOutput = visualCircuit.step(
            leftVisualMotion: motion.left,
            rightVisualMotion: motion.right,
            deltaTime: deltaTime
        )
    }

    private func updateFullCNS(deltaTime: Double, stimulus: FlyStimulus) {
        guard let fullCNSRuntime else { return }
        let motion = visualMotionInput(stimulus: stimulus)
        latestFullCNSMetrics = fullCNSRuntime.step(
            deltaTime: deltaTime,
            input: FullCNSSensoryInput(
                leftVisualMotion: motion.left,
                rightVisualMotion: motion.right,
                odor: max(stimulus.amberOdor, stimulus.berryOdor),
                taste: stimulus.foodContact,
                touch: max(stimulus.touch, stimulus.threat),
                proprioception: Self.clamp(
                    latestEmbodiedOutput.forwardSpeed / 0.13
                        + latestEmbodiedOutput.wingDrive * 0.35
                ),
                hunger: 1 - energy,
                reward: latestEmbodiedOutput.feedingDrive * stimulus.foodContact,
                punishment: max(stimulus.threat, stimulus.touch)
            )
        )
    }

    private func visualMotionInput(stimulus: FlyStimulus) -> (left: Double, right: Double) {
        let visualDrive = Self.clamp(max(stimulus.novelty, stimulus.threat * 0.9))
        let bearing = stimulus.visualMotionBearingRadians ?? stimulus.threatBearingRadians
        let lateral: Double
        if let bearing {
            lateral = sin(Self.normalizedAngle(bearing - headingRadians))
        } else {
            lateral = 0
        }
        return (
            left: visualDrive * Self.clamp(0.62 + lateral * 0.38),
            right: visualDrive * Self.clamp(0.62 - lateral * 0.38)
        )
    }

    private func updateLearningCircuit(deltaTime: Double, stimulus: FlyStimulus) {
        let reward = latestEmbodiedOutput.feedingDrive * stimulus.foodContact
        let punishment = max(stimulus.threat, stimulus.touch)
        guard reward > 0 || punishment > 0 else { return }
        latestLearningOutput = learningCircuit.step(
            amberOdor: stimulus.amberOdor,
            berryOdor: stimulus.berryOdor,
            rewardSignal: reward,
            punishmentSignal: punishment,
            deltaTime: deltaTime
        )
    }

    private func readLearningCircuit(stimulus: FlyStimulus) {
        latestLearningOutput = learningCircuit.read(
            amberOdor: stimulus.amberOdor,
            berryOdor: stimulus.berryOdor
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
                + (latestFullCNSMetrics?.meanActivity ?? 0) * 8
        )
        neuralActivity = Self.approach(neuralActivity, activityTarget, rate: 2.2 * deltaTime)
    }

    private func makeSnapshot(now: Date, stimulus: FlyStimulus) -> FlyStateSnapshot {
        let hunger = 1 - energy
        let emotion = classifyEmotion(hunger: hunger)
        let controllerCircuit = fullCNSRuntime == nil
            ? EmbodiedNeuralController.circuitID
            : "MaleCNS-FULL-CNS→\(EmbodiedNeuralController.circuitID)"
        let controllerProvenance = fullCNSRuntime == nil
            ? EmbodiedNeuralController.provenance
            : "observed/predicted + fitted/assumed readout"
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
            controllerCircuit: controllerCircuit,
            controllerProvenance: controllerProvenance,
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
            wholeCNSDataset: latestFullCNSMetrics?.dataset,
            wholeCNSGraphSHA256: latestFullCNSMetrics?.graphSha256,
            wholeCNSNodeCount: latestFullCNSMetrics?.nodeCount,
            wholeCNSEdgeCount: latestFullCNSMetrics?.edgeCount,
            wholeCNSActiveNeuronCount: latestFullCNSMetrics?.activeNeuronCount,
            wholeCNSSpikeCount: latestFullCNSMetrics?.spikeCount,
            wholeCNSEdgeEventCount: latestFullCNSMetrics?.edgeEventCount,
            wholeCNSRealTimeFactor: latestFullCNSMetrics?.realTimeFactor,
            wholeCNSSensoryActivity: latestFullCNSMetrics?.sensoryActivity,
            wholeCNSCentralComplexActivity: latestFullCNSMetrics?.centralComplexActivity,
            wholeCNSDescendingActivity: latestFullCNSMetrics?.descendingActivity,
            wholeCNSMotorActivity: latestFullCNSMetrics?.motorActivity,
            wholeCNSDopamineLevel: latestFullCNSMetrics?.dopamineLevel,
            wholeCNSSerotoninLevel: latestFullCNSMetrics?.serotoninLevel,
            wholeCNSOctopamineLevel: latestFullCNSMetrics?.octopamineLevel,
            wholeCNSPlasticSynapseSourceCount: latestFullCNSMetrics?.plasticSynapseSourceCount,
            wholeCNSEventBudgetSaturated: latestFullCNSMetrics?.eventBudgetSaturated,
            functionalSelf: functionalSelfModel.state,
            counterfactualSelf: developmentalSelfModel.counterfactual,
            semanticSelf: developmentalSelfModel.semantic,
            socialSelf: developmentalSelfModel.social,
            positionX: positionX,
            positionY: positionY,
            headingRadians: headingRadians,
            reason: reason(for: behavior, stimulus: stimulus),
            modelFidelity: modelFidelity
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
        let prefix = fullCNSRuntime == nil
            ? "\(latestEmbodiedOutput.selectedActionNeuron) 在神经竞争中胜出"
            : "MaleCNS 全 CNS 读出调制后，\(latestEmbodiedOutput.selectedActionNeuron) 胜出"
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

    private static func clampSigned(_ value: Double) -> Double {
        min(max(value, -1), 1)
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
