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

struct SelfTestReport: Encodable {
    let snapshot: FlyStateSnapshot
    let learning: LearningCheck
    let food: FoodCheck
    let neuralControl: NeuralControlCheck
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

guard amberMemory.currentLearnedValence > 0.2,
      berryMemory.currentLearnedValence < -0.2,
      !food.isAvailable(at: baseDate),
      snapshot.modelFidelity == .embodiedNeural,
      snapshot.controllerProvenance == EmbodiedNeuralController.provenance,
      snapshot.selectedActionNeuron != nil,
      ablationStoppedMotion,
      ablationStoppedFeeding else {
    fatalError("V0.4 embodied-neural self-test failed")
}

let report = SelfTestReport(
    snapshot: snapshot,
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
    )
)

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(report)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
