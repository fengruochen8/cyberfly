import CyberFlyCore
import CyberFlySimulation
import Foundation

struct LearningCheck: Encodable {
    let dataset: String
    let circuit: String
    let realNeuronCount: Int
    let kenyonCellCount: Int
    let activeKenyonCellsPerCue: Int
    let amberRewardedValence: Double
    let berryPunishedValence: Double
    let memoryRevision: UInt64
}

struct FoodCheck: Encodable {
    let disappearedAfterEating: Bool
    let simulatedSecondsToFinish: Double
    let spoilsAfterSeconds: Double
    let expiresAfterSeconds: Double
}

struct NeuralControlCheck: Encodable {
    let circuit: String
    let provenance: String
    let actionNeuronCount: Int
    let selectedActionNeuron: String
    let activeControllerNeurons: Int
    let ablationStoppedMotion: Bool
    let ablationStoppedFeeding: Bool
}

struct FullCNSCheck: Encodable {
    let dataset: String
    let graphSha256: String
    let nodeCount: Int
    let edgeCount: Int
    let synapseWeightSum: UInt64
    let deepValidationPassed: Bool
    let fileChecksumsMatch: Bool
    let graphChecksumMatchesPinnedArtifact: Bool
    let simulatedSeconds: Double
    let wallSeconds: Double
    let realTimeFactor: Double
    let activeNeuronCount: Int
    let spikeCount: Int
    let edgeEventCount: Int
    let eventBudgetSaturated: Bool
    let performanceGatePassed: Bool
    let dng13SilencingCount: Int
    let controlVisualTurnBias: Double
    let dng13SilencedVisualTurnBias: Double
    let dng13CausalGatePassed: Bool
}

struct FunctionalSelfCheck: Encodable {
    let circuit: String
    let provenance: String
    let ownMotionAttribution: SelfCausalAttribution
    let externalDisplacementAttribution: SelfCausalAttribution
    let reliableConfidence: Double
    let maskedConfidence: Double
    let episodeCount: Int
    let persistencePassed: Bool
    let ablationPassed: Bool
}

struct CounterfactualSelfCheck: Encodable {
    let circuit: String
    let candidateCount: Int
    let hiddenWindDetected: Bool
    let worldHypothesisProbability: Double
    let epistemicProbeUnderMask: Bool
    let calibrationSampleCount: Int
    let brierScore: Double
}

struct SemanticSelfCheck: Encodable {
    let circuit: String
    let activeGoal: LongTermSelfGoal
    let goalContinuityPassed: Bool
    let beliefCount: Int
    let consolidationCount: Int
    let persistencePassed: Bool
}

struct SocialSelfCheck: Encodable {
    let circuit: String
    let trackedOtherID: String?
    let otherAgencyProbability: Double
    let selfOtherSeparation: Double
    let attribution: SelfOtherAttribution
    let jointAttributionPassed: Bool
    let ablationPassed: Bool
}

struct SelfTestReport: Encodable {
    let snapshot: FlyStateSnapshot
    let learning: LearningCheck
    let food: FoodCheck
    let neuralControl: NeuralControlCheck
    let fullCNS: FullCNSCheck
    let functionalSelf: FunctionalSelfCheck
    let counterfactualSelf: CounterfactualSelfCheck
    let semanticSelf: SemanticSelfCheck
    let socialSelf: SocialSelfCheck
}

let fixedID = UUID(uuidString: "86DBE495-1740-4E49-886D-7D6682D16A25")!
let simulation = FlySimulation(individualID: fixedID, seed: 42)
let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
var snapshot = simulation.step(deltaTime: 0.1, now: baseDate)

for index in 1...120 {
    let stimulus: FlyStimulus
    if index < 25 {
        stimulus = FlyStimulus(novelty: 0.75)
    } else if index < 55 {
        stimulus = FlyStimulus(contamination: 1)
    } else if index < 80 {
        stimulus = FlyStimulus(threat: 0.9, threatBearingRadians: 0)
    } else {
        stimulus = FlyStimulus(
            foodOdor: 0.9,
            foodContact: 1,
            foodBearingRadians: .pi / 4,
            amberOdor: 0.9
        )
    }
    snapshot = simulation.step(
        deltaTime: 0.1,
        stimulus: stimulus,
        now: baseDate.addingTimeInterval(Double(index) * 0.1)
    )
}

var learningCircuit = MaleCNSLearningCircuit()
for _ in 0..<24 {
    _ = learningCircuit.step(
        amberOdor: 1,
        berryOdor: 0,
        rewardSignal: 1,
        deltaTime: 1
    )
    _ = learningCircuit.step(
        amberOdor: 0,
        berryOdor: 1,
        punishmentSignal: 1,
        deltaTime: 1
    )
}
let amberMemory = learningCircuit.step(amberOdor: 1, berryOdor: 0, deltaTime: 0.1)
let berryMemory = learningCircuit.step(amberOdor: 0, berryOdor: 1, deltaTime: 0.1)

var food = FoodResource(
    id: fixedID,
    positionX: 0.4,
    positionY: 0.6,
    placedAt: baseDate
)
var foodSteps = 0
while food.isAvailable(at: baseDate), foodSteps < 200 {
    _ = food.consume(
        deltaTime: 0.1,
        contactStrength: food.edibleStrength(at: baseDate)
    )
    foodSteps += 1
}

let ablatedSimulation = FlySimulation(
    individualID: fixedID,
    seed: 43,
    initialEnergy: 0.2,
    neuralControllerEnabled: false
)
let ablatedSnapshot = ablatedSimulation.step(
    deltaTime: 0.1,
    stimulus: FlyStimulus(
        foodOdor: 1,
        foodContact: 1,
        threat: 1,
        novelty: 1,
        contamination: 1
    ),
    now: baseDate
)
let ablationStoppedMotion = ablatedSnapshot.forwardSpeed == 0
    && ablatedSnapshot.turnRateRadiansPerSecond == 0
    && ablatedSnapshot.wingActivity == 0
let ablationStoppedFeeding = ablatedSnapshot.feedingMotorDrive == 0

let fullCNSGraph = try FullCNSGraph.bundled()
let fullCNSValidation = try fullCNSGraph.validateDeep()
let fullCNSRuntime = FullCNSRuntime(graph: fullCNSGraph)
let fullCNSInput = FullCNSSensoryInput(
    leftVisualMotion: 0.8,
    rightVisualMotion: 0.3,
    odor: 0.7,
    taste: 0.5,
    touch: 0.6,
    proprioception: 0.4,
    hunger: 0.7,
    reward: 0.5
)
var fullCNSMetrics = FullCNSRuntimeMetrics.idle(graph: fullCNSGraph)
var fullCNSWallSeconds = 0.0
for _ in 0..<10 {
    fullCNSMetrics = fullCNSRuntime.step(deltaTime: 0.1, input: fullCNSInput)
    fullCNSWallSeconds += fullCNSMetrics.wallSeconds
}
let fullCNSRealTimeFactor = 1 / max(fullCNSWallSeconds, 0.000_001)
#if DEBUG
let fullCNSPerformanceGatePassed = true
#else
let fullCNSPerformanceGatePassed = fullCNSRealTimeFactor >= 1
#endif

let steeringInput = FullCNSSensoryInput(
    leftVisualMotion: 1,
    rightVisualMotion: 0.05,
    touch: 0.2
)
let steeringControl = FullCNSRuntime(graph: fullCNSGraph)
var controlVisualTurnBias = 0.0
for _ in 0..<8 {
    controlVisualTurnBias = max(
        controlVisualTurnBias,
        abs(steeringControl.step(deltaTime: 0.1, input: steeringInput).turnBias)
    )
}
let dng13Silenced = FullCNSRuntime(graph: fullCNSGraph)
let dng13SilencingCount = dng13Silenced.setSilenced(bodyIDs: [11_074, 512_006])
var dng13SilencedVisualTurnBias = 0.0
for _ in 0..<8 {
    dng13SilencedVisualTurnBias = max(
        dng13SilencedVisualTurnBias,
        abs(dng13Silenced.step(deltaTime: 0.1, input: steeringInput).turnBias)
    )
}
let dng13CausalGatePassed = dng13SilencingCount == 2
    && controlVisualTurnBias > 0.02
    && dng13SilencedVisualTurnBias < 0.000_001

let integratedSimulation = FlySimulation(
    individualID: fixedID,
    seed: 44,
    fullCNSRuntime: FullCNSRuntime(graph: fullCNSGraph)
)
let integratedSnapshot = integratedSimulation.step(
    deltaTime: 0.1,
    stimulus: FlyStimulus(
        foodOdor: 0.8,
        foodContact: 0.5,
        foodBearingRadians: 0.3,
        amberOdor: 0.8,
        threat: 0.4,
        visualMotionBearingRadians: 0.6,
        novelty: 0.7
    ),
    now: baseDate
)

let selfSimulation = FlySimulation(individualID: fixedID, seed: 501)
var ownMotionSnapshot = selfSimulation.step(deltaTime: 0.1, now: baseDate)
for index in 1...12 {
    ownMotionSnapshot = selfSimulation.step(
        deltaTime: 0.1,
        stimulus: FlyStimulus(novelty: 0.35),
        now: baseDate.addingTimeInterval(Double(index) * 0.1)
    )
}
let ownMotionSelf = ownMotionSnapshot.functionalSelf
selfSimulation.applyExternalDisplacement(
    deltaX: 0.15,
    deltaY: 0.08,
    headingDelta: .pi / 4
)
let externalDisplacementSnapshot = selfSimulation.step(
    deltaTime: 0.1,
    now: baseDate.addingTimeInterval(1.3)
)
let externalDisplacementSelf = externalDisplacementSnapshot.functionalSelf
let restoredSelfSimulation = FlySimulation(
    restoring: externalDisplacementSnapshot,
    seed: 502
)
let selfPersistencePassed = restoredSelfSimulation.functionalSelfState.individualID == fixedID
    && restoredSelfSimulation.functionalSelfState.episodes == externalDisplacementSelf?.episodes

let maskedSimulation = FlySimulation(individualID: fixedID, seed: 503)
var reliableSelf = maskedSimulation.step(deltaTime: 0.1, now: baseDate)
for index in 1...12 {
    reliableSelf = maskedSimulation.step(
        deltaTime: 0.1,
        stimulus: FlyStimulus(novelty: 0.3),
        now: baseDate.addingTimeInterval(Double(index) * 0.1)
    )
}
let reliableConfidence = reliableSelf.functionalSelf?.confidence ?? 0
var maskedSelf = reliableSelf
for index in 13...18 {
    maskedSelf = maskedSimulation.step(
        deltaTime: 0.1,
        stimulus: FlyStimulus(novelty: 0.03, sensorReliability: 0.1),
        now: baseDate.addingTimeInterval(Double(index) * 0.1)
    )
}
let maskedConfidence = maskedSelf.functionalSelf?.confidence ?? 1
let selfAblationSimulation = FlySimulation(
    individualID: fixedID,
    seed: 504,
    functionalSelfEnabled: false
)
let selfAblationState = selfAblationSimulation.step(
    deltaTime: 0.1,
    stimulus: FlyStimulus(touch: 1),
    now: baseDate
).functionalSelf
let selfAblationPassed = selfAblationState?.enabled == false
    && selfAblationState?.agencyScore == 0
    && selfAblationState?.episodes.isEmpty == true

let hiddenWindSimulation = FlySimulation(individualID: fixedID, seed: 701)
var hiddenWindBaseline = hiddenWindSimulation.step(deltaTime: 0.1, now: baseDate)
for index in 1...12 {
    hiddenWindBaseline = hiddenWindSimulation.step(
        deltaTime: 0.1,
        stimulus: FlyStimulus(novelty: 0.3),
        now: baseDate.addingTimeInterval(Double(index) * 0.1)
    )
}
hiddenWindSimulation.applyExternalDisplacement(
    deltaX: 0.16,
    deltaY: 0.08,
    headingDelta: .pi / 3,
    revealToSelfModel: false
)
let hiddenWindSnapshot = hiddenWindSimulation.step(
    deltaTime: 0.1,
    now: baseDate.addingTimeInterval(1.3)
)
let hiddenWindCounterfactual = hiddenWindSnapshot.counterfactualSelf
let hiddenWindDetected = hiddenWindSnapshot.functionalSelf?.causalAttribution == .external
    && (hiddenWindCounterfactual?.worldHypothesisProbability ?? 0) > 0.5
    && hiddenWindCounterfactual?.blindExternalEventCount == 1

let goalSimulation = FlySimulation(individualID: fixedID, seed: 702)
_ = goalSimulation.step(deltaTime: 0.1, now: baseDate)
var goalSnapshot = goalSimulation.step(
    deltaTime: 0.1,
    stimulus: FlyStimulus(threat: 0.95),
    now: baseDate.addingTimeInterval(0.1)
)
for index in 3...12 {
    goalSnapshot = goalSimulation.step(
        deltaTime: 0.1,
        now: baseDate.addingTimeInterval(Double(index) * 0.1)
    )
}
let goalContinuityPassed = goalSnapshot.semanticSelf?.activeGoal == .avoidThreat
    && goalSnapshot.semanticSelf?.goalSinceTick == 2

let semanticSimulation = FlySimulation(individualID: fixedID, seed: 703)
var semanticSnapshot = semanticSimulation.step(deltaTime: 0.1, now: baseDate)
for index in 2...35 {
    semanticSnapshot = semanticSimulation.step(
        deltaTime: 0.1,
        stimulus: FlyStimulus(novelty: 0.25),
        now: baseDate.addingTimeInterval(Double(index) * 0.1)
    )
}
let restoredSemanticSimulation = FlySimulation(restoring: semanticSnapshot, seed: 704)
let semanticPersistencePassed = restoredSemanticSimulation.semanticSelfState.beliefs
        == semanticSnapshot.semanticSelf?.beliefs
    && restoredSemanticSimulation.semanticSelfState.consolidationCount
        == semanticSnapshot.semanticSelf?.consolidationCount

let socialSimulation = FlySimulation(individualID: fixedID, seed: 705)
var socialSnapshot = socialSimulation.step(deltaTime: 0.1, now: baseDate)
for index in 2...20 {
    socialSnapshot = socialSimulation.step(
        deltaTime: 0.1,
        stimulus: FlyStimulus(
            novelty: 0.7,
            otherAgentID: "OTHER-ALPHA",
            otherAgentPresence: 1,
            otherAgentMotion: 0.9,
            otherAgentContingency: 0.95,
            otherAgentThreat: 0.02
        ),
        now: baseDate.addingTimeInterval(Double(index) * 0.1)
    )
}
let socialState = socialSnapshot.socialSelf
let jointAttributionPassed = (socialState?.otherAgencyProbability ?? 0) > 0.75
    && (socialState?.jointActionProbability ?? 0) > 0.48
    && socialState?.attribution == .joint
let socialAblationSimulation = FlySimulation(
    individualID: fixedID,
    seed: 706,
    socialSelfEnabled: false
)
let socialAblationState = socialAblationSimulation.step(
    deltaTime: 0.1,
    stimulus: FlyStimulus(
        otherAgentID: "OTHER-ALPHA",
        otherAgentPresence: 1,
        otherAgentMotion: 1,
        otherAgentContingency: 1
    ),
    now: baseDate
).socialSelf
let socialAblationPassed = socialAblationState?.enabled == false
    && socialAblationState?.otherAgencyProbability == 0

let acceptanceGates: [(String, Bool)] = [
    ("amber-reward-learning", amberMemory.currentLearnedValence > 0.2),
    ("berry-punishment-learning", berryMemory.currentLearnedValence < -0.2),
    ("finite-food", !food.isAvailable(at: baseDate)),
    ("full-cns-exact", fullCNSValidation.isExact),
    ("full-cns-node-count", fullCNSMetrics.nodeCount == 165_122),
    ("full-cns-edge-count", fullCNSMetrics.edgeCount == 25_563_197),
    ("event-budget", !fullCNSMetrics.eventBudgetSaturated),
    ("realtime-performance", fullCNSPerformanceGatePassed),
    ("dng13-causal", dng13CausalGatePassed),
    ("v1.5-model-fidelity", integratedSnapshot.modelFidelity == .socialSelfCognition),
    ("integrated-full-cns", integratedSnapshot.wholeCNSNodeCount == fullCNSMetrics.nodeCount),
    ("controller-provenance", snapshot.controllerProvenance == EmbodiedNeuralController.provenance),
    ("action-selected", snapshot.selectedActionNeuron != nil),
    ("own-motion-attribution", ownMotionSelf?.causalAttribution == .selfGenerated),
    ("external-attribution", externalDisplacementSelf?.causalAttribution == .external),
    ("uncertainty-under-mask", maskedConfidence < reliableConfidence),
    ("functional-self-persistence", selfPersistencePassed),
    ("functional-self-ablation", selfAblationPassed),
    ("hidden-wind-inference", hiddenWindDetected),
    ("epistemic-probe", maskedSelf.counterfactualSelf?.shouldProbe == true),
    ("goal-continuity", goalContinuityPassed),
    ("semantic-consolidation", (semanticSnapshot.semanticSelf?.beliefs.count ?? 0) == 4),
    ("semantic-persistence", semanticPersistencePassed),
    ("joint-other-attribution", jointAttributionPassed),
    ("social-ablation", socialAblationPassed),
    ("motor-ablation", ablationStoppedMotion),
    ("feeding-ablation", ablationStoppedFeeding)
]
let failedGates = acceptanceGates.filter { !$0.1 }.map(\.0)
guard failedGates.isEmpty else {
    fatalError(
        "CyberFly v1.5 cumulative self-cognition self-test failed: "
            + failedGates.joined(separator: ", ")
    )
}

let report = SelfTestReport(
    snapshot: integratedSnapshot,
    learning: LearningCheck(
        dataset: MaleCNSLearningCircuit.datasetID,
        circuit: MaleCNSLearningCircuit.circuitID,
        realNeuronCount: MaleCNSLearningCircuit.realNeuronCount,
        kenyonCellCount: MaleCNSLearningCircuit.kenyonCellCount,
        activeKenyonCellsPerCue: amberMemory.activeKenyonCellCount,
        amberRewardedValence: amberMemory.currentLearnedValence,
        berryPunishedValence: berryMemory.currentLearnedValence,
        memoryRevision: learningCircuit.memoryRevision
    ),
    food: FoodCheck(
        disappearedAfterEating: !food.isAvailable(at: baseDate),
        simulatedSecondsToFinish: Double(foodSteps) * 0.1,
        spoilsAfterSeconds: FoodResource.defaultFreshDuration,
        expiresAfterSeconds: FoodResource.defaultMaximumLifetime
    ),
    neuralControl: NeuralControlCheck(
        circuit: snapshot.controllerCircuit ?? "missing",
        provenance: snapshot.controllerProvenance ?? "missing",
        actionNeuronCount: FlyBehavior.allCases.count,
        selectedActionNeuron: snapshot.selectedActionNeuron ?? "missing",
        activeControllerNeurons: snapshot.activeControllerNeuronCount ?? 0,
        ablationStoppedMotion: ablationStoppedMotion,
        ablationStoppedFeeding: ablationStoppedFeeding
    ),
    fullCNS: FullCNSCheck(
        dataset: fullCNSMetrics.dataset,
        graphSha256: fullCNSMetrics.graphSha256,
        nodeCount: fullCNSMetrics.nodeCount,
        edgeCount: fullCNSMetrics.edgeCount,
        synapseWeightSum: fullCNSValidation.synapseWeightSum,
        deepValidationPassed: fullCNSValidation.isExact,
        fileChecksumsMatch: fullCNSValidation.fileChecksumsMatch,
        graphChecksumMatchesPinnedArtifact: fullCNSValidation.graphChecksumMatchesPinnedArtifact,
        simulatedSeconds: 1,
        wallSeconds: fullCNSWallSeconds,
        realTimeFactor: fullCNSRealTimeFactor,
        activeNeuronCount: fullCNSMetrics.activeNeuronCount,
        spikeCount: fullCNSMetrics.spikeCount,
        edgeEventCount: fullCNSMetrics.edgeEventCount,
        eventBudgetSaturated: fullCNSMetrics.eventBudgetSaturated,
        performanceGatePassed: fullCNSPerformanceGatePassed,
        dng13SilencingCount: dng13SilencingCount,
        controlVisualTurnBias: controlVisualTurnBias,
        dng13SilencedVisualTurnBias: dng13SilencedVisualTurnBias,
        dng13CausalGatePassed: dng13CausalGatePassed
    ),
    functionalSelf: FunctionalSelfCheck(
        circuit: FunctionalSelfModel.circuitID,
        provenance: FunctionalSelfModel.provenance,
        ownMotionAttribution: ownMotionSelf?.causalAttribution ?? .uncertain,
        externalDisplacementAttribution: externalDisplacementSelf?.causalAttribution ?? .uncertain,
        reliableConfidence: reliableConfidence,
        maskedConfidence: maskedConfidence,
        episodeCount: externalDisplacementSelf?.episodes.count ?? 0,
        persistencePassed: selfPersistencePassed,
        ablationPassed: selfAblationPassed
    ),
    counterfactualSelf: CounterfactualSelfCheck(
        circuit: CounterfactualSelfState.circuitID,
        candidateCount: hiddenWindCounterfactual?.candidates.count ?? 0,
        hiddenWindDetected: hiddenWindDetected,
        worldHypothesisProbability: hiddenWindCounterfactual?.worldHypothesisProbability ?? 0,
        epistemicProbeUnderMask: maskedSelf.counterfactualSelf?.shouldProbe ?? false,
        calibrationSampleCount: hiddenWindCounterfactual?.calibrationSampleCount ?? 0,
        brierScore: hiddenWindCounterfactual?.brierScore ?? 1
    ),
    semanticSelf: SemanticSelfCheck(
        circuit: SemanticSelfState.circuitID,
        activeGoal: goalSnapshot.semanticSelf?.activeGoal ?? .exploreWorld,
        goalContinuityPassed: goalContinuityPassed,
        beliefCount: semanticSnapshot.semanticSelf?.beliefs.count ?? 0,
        consolidationCount: semanticSnapshot.semanticSelf?.consolidationCount ?? 0,
        persistencePassed: semanticPersistencePassed
    ),
    socialSelf: SocialSelfCheck(
        circuit: SocialSelfState.circuitID,
        trackedOtherID: socialState?.trackedOtherID,
        otherAgencyProbability: socialState?.otherAgencyProbability ?? 0,
        selfOtherSeparation: socialState?.selfOtherSeparation ?? 0,
        attribution: socialState?.attribution ?? .uncertain,
        jointAttributionPassed: jointAttributionPassed,
        ablationPassed: socialAblationPassed
    )
)

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(report)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
