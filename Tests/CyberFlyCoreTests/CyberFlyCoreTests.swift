import CyberFlyCore
import CyberFlySimulation
import Foundation
import XCTest

final class CyberFlyCoreTests: XCTestCase {
    private let fixedID = UUID(uuidString: "86DBE495-1740-4E49-886D-7D6682D16A25")!
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testSnapshotRoundTripThroughStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FlySnapshotStore(fileURL: directory.appendingPathComponent("state.json"))
        let snapshot = FlyStateSnapshot.preview(now: fixedDate)

        try store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
    }

    func testSimulationIsDeterministicForTheSameSeed() {
        let first = FlySimulation(individualID: fixedID, seed: 99)
        let second = FlySimulation(individualID: fixedID, seed: 99)
        let stimulus = FlyStimulus(foodOdor: 0.4, novelty: 0.8, contamination: 0.3)

        var firstSnapshot = first.step(deltaTime: 0.1, stimulus: stimulus, now: fixedDate)
        var secondSnapshot = second.step(deltaTime: 0.1, stimulus: stimulus, now: fixedDate)
        for index in 1...80 {
            let date = fixedDate.addingTimeInterval(Double(index) * 0.1)
            firstSnapshot = first.step(deltaTime: 0.1, stimulus: stimulus, now: date)
            secondSnapshot = second.step(deltaTime: 0.1, stimulus: stimulus, now: date)
        }

        XCTAssertEqual(firstSnapshot, secondSnapshot)
    }

    func testEveryBehaviorHasAnExplicitEngineeredActionNeuron() {
        let neuronIDs = FlyBehavior.allCases.map(EmbodiedNeuralController.actionNeuronID)

        XCTAssertEqual(neuronIDs.count, FlyBehavior.allCases.count)
        XCTAssertEqual(Set(neuronIDs).count, FlyBehavior.allCases.count)
        XCTAssertTrue(neuronIDs.allSatisfy { $0.hasPrefix("ENG-ACT-") })
        XCTAssertEqual(EmbodiedNeuralController.provenance, "fitted/assumed")
    }

    func testEveryBehaviorCanBeSelectedByNeuralPopulationCompetition() {
        let cases: [(FlyBehavior, EmbodiedNeuralInput)] = [
            (.idle, EmbodiedNeuralInput(energy: 1, fatigue: 0, arousal: 0, curiosity: 0)),
            (.exploring, EmbodiedNeuralInput(energy: 1, fatigue: 0, arousal: 0, curiosity: 1)),
            (.walking, EmbodiedNeuralInput(energy: 1, fatigue: 0, arousal: 1, curiosity: 0)),
            (.foraging, EmbodiedNeuralInput(energy: 0.2, foodOdor: 1)),
            (
                .avoidingOdor,
                EmbodiedNeuralInput(
                    energy: 1,
                    foodOdor: 1,
                    learnedValence: -1,
                    memoryConfidence: 1
                )
            ),
            (.feeding, EmbodiedNeuralInput(energy: 0.2, foodOdor: 1, foodContact: 1)),
            (
                .flying,
                EmbodiedNeuralInput(
                    energy: 1,
                    fatigue: 0,
                    arousal: 1,
                    curiosity: 1,
                    novelty: 1
                )
            ),
            (
                .groomingHead,
                EmbodiedNeuralInput(
                    energy: 1,
                    fatigue: 0,
                    arousal: 0,
                    groomingNeed: 1
                )
            ),
            (
                .groomingWings,
                EmbodiedNeuralInput(
                    energy: 1,
                    fatigue: 0,
                    arousal: 1,
                    groomingNeed: 1
                )
            ),
            (.resting, EmbodiedNeuralInput(energy: 1, fatigue: 1, arousal: 0, curiosity: 0)),
            (.startled, EmbodiedNeuralInput(energy: 1, threat: 1)),
            (.torpor, EmbodiedNeuralInput(lifeState: .torpor, energy: 0.001))
        ]

        for (expectedBehavior, input) in cases {
            var controller = EmbodiedNeuralController()
            let output = controller.step(input: input, deltaTime: 0.1, neuralNoise: 0)
            XCTAssertEqual(
                output.behavior,
                expectedBehavior,
                "Expected neural population for \(expectedBehavior.rawValue) to win"
            )
            XCTAssertEqual(
                output.selectedActionNeuron,
                EmbodiedNeuralController.actionNeuronID(for: expectedBehavior)
            )
        }
    }

    func testDescendingMotorOutputsComeFromNeuralController() {
        var foragingController = EmbodiedNeuralController()
        let foraging = foragingController.step(
            input: EmbodiedNeuralInput(
                energy: 0.2,
                foodOdor: 1,
                foodBearingRadians: .pi / 2,
                headingRadians: 0
            ),
            deltaTime: 0.1,
            neuralNoise: 0
        )
        XCTAssertEqual(foraging.behavior, .foraging)
        XCTAssertGreaterThan(foraging.forwardSpeed, 0)
        XCTAssertGreaterThan(foraging.turnRateRadiansPerSecond, 0)
        XCTAssertEqual(foraging.wingDrive, 0, accuracy: 0.0001)

        var feedingController = EmbodiedNeuralController()
        let feeding = feedingController.step(
            input: EmbodiedNeuralInput(energy: 0.2, foodOdor: 1, foodContact: 1),
            deltaTime: 0.1,
            neuralNoise: 0
        )
        XCTAssertEqual(feeding.behavior, .feeding)
        XCTAssertGreaterThan(feeding.feedingDrive, 0)
        XCTAssertEqual(feeding.forwardSpeed, 0, accuracy: 0.0001)

        var flightController = EmbodiedNeuralController()
        let flight = flightController.step(
            input: EmbodiedNeuralInput(
                energy: 1,
                fatigue: 0,
                arousal: 1,
                curiosity: 1,
                novelty: 1
            ),
            deltaTime: 0.1,
            neuralNoise: 0
        )
        XCTAssertEqual(flight.behavior, .flying)
        XCTAssertGreaterThan(flight.wingDrive, 0)
    }

    func testSilencingControllerAblatesBehaviorAndMotorActivity() {
        let simulation = FlySimulation(
            individualID: fixedID,
            seed: 47,
            initialEnergy: 0.2,
            neuralControllerEnabled: false,
            configuration: .acceleratedTests
        )
        let stimulus = FlyStimulus(
            foodOdor: 1,
            foodContact: 1,
            foodBearingRadians: .pi / 2,
            threat: 1,
            threatBearingRadians: 0,
            novelty: 1,
            contamination: 1
        )
        let initial = simulation.step(deltaTime: 0.1, stimulus: stimulus, now: fixedDate)
        let next = simulation.step(
            deltaTime: 0.5,
            stimulus: stimulus,
            now: fixedDate.addingTimeInterval(0.5)
        )

        XCTAssertEqual(next.behavior, .idle)
        XCTAssertEqual(next.activeControllerNeuronCount, 0)
        XCTAssertEqual(next.forwardSpeed, 0)
        XCTAssertEqual(next.turnRateRadiansPerSecond, 0)
        XCTAssertEqual(next.wingActivity, 0)
        XCTAssertEqual(next.feedingMotorDrive, 0)
        XCTAssertEqual(next.positionX, initial.positionX, accuracy: 0.0001)
        XCTAssertEqual(next.positionY, initial.positionY, accuracy: 0.0001)
        XCTAssertLessThan(next.energy, initial.energy)
    }

    func testOfficialMaleCNSVisualCircuitProducesSpikes() {
        var circuit = MaleCNSVisualCircuit()
        var totalSpikes = 0
        var activeNeuronIDsSeen = 0
        var peakDNg13Rate = 0.0
        var peakTurnBias = 0.0
        var peakLoVP92Rate = 0.0
        var peakVES200mRate = 0.0

        for _ in 0..<25 {
            let output = circuit.step(
                leftVisualMotion: 1,
                rightVisualMotion: 0.1,
                deltaTime: 0.02
            )
            totalSpikes += output.totalSpikes
            activeNeuronIDsSeen = max(activeNeuronIDsSeen, output.activeNeuronCount)
            peakDNg13Rate = max(
                peakDNg13Rate,
                output.leftDNg13RateHz,
                output.rightDNg13RateHz
            )
            peakTurnBias = max(peakTurnBias, abs(output.turnBias))
            peakLoVP92Rate = max(peakLoVP92Rate, output.loVP92RateHz)
            peakVES200mRate = max(peakVES200mRate, output.ves200mRateHz)
        }

        XCTAssertEqual(MaleCNSVisualCircuit.datasetID, "male-cns:v1.0")
        XCTAssertEqual(MaleCNSVisualCircuit.realNeuronCount, 27)
        XCTAssertEqual(MaleCNSVisualCircuit.sourceSHA256.count, 3)
        XCTAssertGreaterThan(totalSpikes, 0)
        XCTAssertGreaterThan(activeNeuronIDsSeen, 0)
        XCTAssertGreaterThan(peakLoVP92Rate, 0)
        XCTAssertGreaterThan(peakVES200mRate, 0)
        XCTAssertGreaterThan(peakDNg13Rate, 0)
        XCTAssertGreaterThan(peakTurnBias, 0)
    }

    func testSimulationRestoresPersistentIndividualState() {
        let first = FlySimulation(individualID: fixedID, seed: 61)
        var saved = first.step(deltaTime: 0.1, now: fixedDate)
        for index in 1...40 {
            saved = first.step(
                deltaTime: 0.1,
                stimulus: FlyStimulus(novelty: 0.8, contamination: 0.3),
                now: fixedDate.addingTimeInterval(Double(index) * 0.1)
            )
        }

        let restored = FlySimulation(restoring: saved, seed: 62)
        let resumed = restored.step(
            deltaTime: 0.001,
            now: fixedDate.addingTimeInterval(5)
        )

        XCTAssertEqual(resumed.individualID, saved.individualID)
        XCTAssertEqual(resumed.tick, saved.tick + 1)
        XCTAssertEqual(resumed.lifeState, saved.lifeState)
        XCTAssertEqual(resumed.energy, saved.energy, accuracy: 0.0001)
        XCTAssertEqual(resumed.positionX, saved.positionX, accuracy: 0.001)
        XCTAssertEqual(resumed.positionY, saved.positionY, accuracy: 0.001)
        XCTAssertEqual(resumed.curiosity, saved.curiosity, accuracy: 0.001)
    }

    func testHungerIncreasesAsEnergyIsConsumed() {
        let simulation = FlySimulation(
            individualID: fixedID,
            seed: 1,
            initialEnergy: 0.8,
            configuration: .acceleratedTests
        )
        let initial = simulation.step(deltaTime: 0.1, now: fixedDate)
        var latest = initial
        for index in 1...20 {
            latest = simulation.step(
                deltaTime: 0.5,
                now: fixedDate.addingTimeInterval(Double(index) * 0.5)
            )
        }

        XCTAssertGreaterThan(latest.hunger, initial.hunger)
        XCTAssertLessThan(latest.energy, initial.energy)
    }

    func testFoodContactSelectsFeedingWhenHungryAndRestoresEnergy() {
        let simulation = FlySimulation(
            individualID: fixedID,
            seed: 7,
            initialEnergy: 0.12,
            configuration: .acceleratedTests
        )
        let food = FlyStimulus(foodOdor: 1, foodContact: 1, foodBearingRadians: 0)
        let selected = simulation.step(deltaTime: 0.1, stimulus: food, now: fixedDate)
        let afterFeeding = simulation.step(
            deltaTime: 0.5,
            stimulus: food,
            now: fixedDate.addingTimeInterval(0.5)
        )

        XCTAssertEqual(selected.behavior, .feeding)
        XCTAssertGreaterThan(afterFeeding.energy, selected.energy)
    }

    func testFoodIsFiniteAndDisappearsAfterBeingConsumed() {
        var food = FoodResource(
            id: fixedID,
            positionX: 0.4,
            positionY: 0.6,
            placedAt: fixedDate,
            remainingPortion: 0.2
        )

        XCTAssertTrue(food.isAvailable(at: fixedDate))
        XCTAssertTrue(food.consume(deltaTime: 2, contactStrength: 1, ratePerSecond: 0.1))
        XCTAssertEqual(food.remainingPortion, 0, accuracy: 0.0001)
        XCTAssertFalse(food.isAvailable(at: fixedDate))
        XCTAssertEqual(food.odorStrength(at: fixedDate), 0)
    }

    func testFoodSpoilsAndExpiresByWallClockAge() {
        let food = FoodResource(
            id: fixedID,
            positionX: 0.4,
            positionY: 0.6,
            placedAt: fixedDate,
            freshDuration: 10,
            maximumLifetime: 20
        )

        XCTAssertEqual(food.phase(at: fixedDate.addingTimeInterval(9)), .fresh)
        XCTAssertEqual(food.phase(at: fixedDate.addingTimeInterval(15)), .spoiling)
        XCTAssertEqual(food.freshness(at: fixedDate.addingTimeInterval(15)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(food.phase(at: fixedDate.addingTimeInterval(20)), .gone)
        XCTAssertFalse(food.isAvailable(at: fixedDate.addingTimeInterval(20)))
        XCTAssertEqual(food.odorStrength(at: fixedDate.addingTimeInterval(20)), 0)
    }

    func testFoodDepletesUnderItsRealContactStrength() {
        var food = FoodResource(
            id: fixedID,
            positionX: 0.4,
            positionY: 0.6,
            placedAt: fixedDate
        )

        for _ in 0..<200 where food.isAvailable(at: fixedDate) {
            let contact = food.edibleStrength(at: fixedDate)
            _ = food.consume(deltaTime: 0.1, contactStrength: contact)
        }

        XCTAssertFalse(food.isAvailable(at: fixedDate))
        XCTAssertLessThanOrEqual(food.remainingPortion, 0.0001)
    }

    func testRewardAndPunishmentFormCueSpecificMemories() {
        var circuit = MaleCNSLearningCircuit()

        for _ in 0..<24 {
            _ = circuit.step(
                amberOdor: 1,
                berryOdor: 0,
                rewardSignal: 1,
                deltaTime: 1
            )
            _ = circuit.step(
                amberOdor: 0,
                berryOdor: 1,
                punishmentSignal: 1,
                deltaTime: 1
            )
        }

        let amber = circuit.step(amberOdor: 1, berryOdor: 0, deltaTime: 0.1)
        let berry = circuit.step(amberOdor: 0, berryOdor: 1, deltaTime: 0.1)

        XCTAssertEqual(MaleCNSLearningCircuit.datasetID, "male-cns:v1.0")
        XCTAssertEqual(MaleCNSLearningCircuit.realNeuronCount, 1_426)
        XCTAssertEqual(MaleCNSLearningCircuit.kenyonCellCount, 1_240)
        XCTAssertEqual(amber.activeKenyonCellCount, 62)
        XCTAssertEqual(berry.activeKenyonCellCount, 62)
        XCTAssertGreaterThan(amber.currentLearnedValence, 0.2)
        XCTAssertLessThan(berry.currentLearnedValence, -0.2)
        XCTAssertGreaterThan(amber.currentMemoryConfidence, 0.2)
        XCTAssertGreaterThan(berry.currentMemoryConfidence, 0.2)
    }

    func testDopamineAblationPreventsPlasticity() {
        var circuit = MaleCNSLearningCircuit(plasticityEnabled: false)

        for _ in 0..<30 {
            _ = circuit.step(
                amberOdor: 1,
                berryOdor: 0,
                rewardSignal: 1,
                deltaTime: 1
            )
        }
        let amber = circuit.step(amberOdor: 1, berryOdor: 0, deltaTime: 0.1)

        XCTAssertEqual(circuit.memoryRevision, 0)
        XCTAssertEqual(amber.currentLearnedValence, 0, accuracy: 0.0001)
        XCTAssertEqual(amber.currentMemoryConfidence, 0, accuracy: 0.0001)
    }

    func testOppositeReinforcementReversesAnOdorMemory() {
        var circuit = MaleCNSLearningCircuit()

        for _ in 0..<18 {
            _ = circuit.step(
                amberOdor: 1,
                berryOdor: 0,
                rewardSignal: 1,
                deltaTime: 1
            )
        }
        let rewarded = circuit.step(amberOdor: 1, berryOdor: 0, deltaTime: 0.1)

        for _ in 0..<36 {
            _ = circuit.step(
                amberOdor: 1,
                berryOdor: 0,
                punishmentSignal: 1,
                deltaTime: 1
            )
        }
        let reversed = circuit.step(amberOdor: 1, berryOdor: 0, deltaTime: 0.1)

        XCTAssertGreaterThan(rewarded.currentLearnedValence, 0.2)
        XCTAssertLessThan(reversed.currentLearnedValence, -0.2)
    }

    func testFeedingWritesRewardMemoryIntoSimulationSnapshot() {
        let simulation = FlySimulation(
            individualID: fixedID,
            seed: 7,
            initialEnergy: 0.12,
            configuration: .acceleratedTests
        )
        let amberFood = FlyStimulus(
            foodOdor: 1,
            foodContact: 1,
            foodBearingRadians: 0,
            amberOdor: 1
        )
        var snapshot = simulation.step(
            deltaTime: 0.1,
            stimulus: amberFood,
            now: fixedDate
        )
        for index in 1...20 {
            snapshot = simulation.step(
                deltaTime: 0.1,
                stimulus: amberFood,
                now: fixedDate.addingTimeInterval(Double(index) * 0.1)
            )
        }

        XCTAssertEqual(snapshot.currentOdorCue, .amber)
        XCTAssertEqual(snapshot.activeKenyonCellCount, 62)
        XCTAssertGreaterThan(snapshot.learnedValence ?? 0, 0.2)
        XCTAssertGreaterThan(snapshot.memoryConfidence ?? 0, 0.1)
        XCTAssertGreaterThan(simulation.learningMemoryRevision, 0)
    }

    func testPunishedOdorMemoryBiasesSimulationTowardAvoidance() {
        var learningCircuit = MaleCNSLearningCircuit()
        for _ in 0..<24 {
            _ = learningCircuit.step(
                amberOdor: 0,
                berryOdor: 1,
                punishmentSignal: 1,
                deltaTime: 1
            )
        }
        let simulation = FlySimulation(
            individualID: fixedID,
            seed: 21,
            initialEnergy: 0.2,
            learningMemory: learningCircuit.exportMemory(now: fixedDate)
        )

        let snapshot = simulation.step(
            deltaTime: 0.1,
            stimulus: FlyStimulus(
                foodOdor: 1,
                foodBearingRadians: 0,
                berryOdor: 1
            ),
            now: fixedDate
        )

        XCTAssertLessThan(snapshot.learnedValence ?? 0, -0.2)
        XCTAssertEqual(snapshot.behavior, .avoidingOdor)
    }

    func testLearningMemoryStoreRoundTripRestoresReadout() throws {
        var circuit = MaleCNSLearningCircuit()
        for _ in 0..<16 {
            _ = circuit.step(
                amberOdor: 1,
                berryOdor: 0,
                rewardSignal: 1,
                deltaTime: 1
            )
        }
        let before = circuit.step(amberOdor: 1, berryOdor: 0, deltaTime: 0.1)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyMemoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaleCNSLearningMemoryStore(
            fileURL: directory.appendingPathComponent("learning-memory.json")
        )

        try store.save(circuit.exportMemory(now: fixedDate))
        let restoredMemory = try XCTUnwrap(store.load())
        var restored = MaleCNSLearningCircuit(memory: restoredMemory)
        let after = restored.step(amberOdor: 1, berryOdor: 0, deltaTime: 0.1)

        XCTAssertEqual(restored.memoryRevision, circuit.memoryRevision)
        XCTAssertEqual(after.currentLearnedValence, before.currentLearnedValence, accuracy: 0.0001)
        XCTAssertEqual(after.currentMemoryConfidence, before.currentMemoryConfidence, accuracy: 0.0001)
    }

    func testSchemaTwoSnapshotDecodesWithoutLearningFields() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(FlyStateSnapshot.preview(now: fixedDate))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = 2
        object["modelFidelity"] = ModelFidelity.hybridConnectome.rawValue
        for key in [
            "learningCircuit",
            "currentOdorCue",
            "learnedValence",
            "memoryConfidence",
            "activeKenyonCellCount",
            "rewardDANActivity",
            "punishmentDANActivity",
            "memorySummary"
        ] {
            object.removeValue(forKey: key)
        }
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(FlyStateSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.modelFidelity, .hybridConnectome)
        XCTAssertNil(decoded.learningCircuit)
        XCTAssertNil(decoded.memorySummary)
    }

    func testThreatInterruptsTheCurrentBehavior() {
        let simulation = FlySimulation(individualID: fixedID, seed: 12)
        _ = simulation.step(deltaTime: 0.1, stimulus: .quiet, now: fixedDate)

        let startled = simulation.step(
            deltaTime: 0.1,
            stimulus: FlyStimulus(threat: 1, threatBearingRadians: 0),
            now: fixedDate.addingTimeInterval(0.1)
        )

        XCTAssertEqual(startled.behavior, .startled)
        XCTAssertGreaterThan(startled.arousal, 0.3)
    }

    func testHighGroomingNeedEventuallySelectsGrooming() {
        let simulation = FlySimulation(individualID: fixedID, seed: 33)
        simulation.addContamination(1)
        var behaviors = Set<FlyBehavior>()

        for index in 0..<120 {
            let snapshot = simulation.step(
                deltaTime: 0.25,
                stimulus: FlyStimulus(contamination: 1),
                now: fixedDate.addingTimeInterval(Double(index) * 0.25)
            )
            behaviors.insert(snapshot.behavior)
        }

        XCTAssertTrue(behaviors.contains(.groomingHead) || behaviors.contains(.groomingWings))
    }

    func testPreviewStatusContainsWidgetMetrics() {
        let snapshot = FlyStateSnapshot.preview(now: fixedDate)

        XCTAssertEqual(snapshot.emotion, .curious)
        XCTAssertEqual(snapshot.behavior, .exploring)
        XCTAssertGreaterThan(snapshot.wellbeing, 0)
        XCTAssertGreaterThan(snapshot.curiosity, 0)
        XCTAssertFalse(snapshot.isStale(relativeTo: fixedDate.addingTimeInterval(60)))
        XCTAssertTrue(snapshot.isStale(relativeTo: fixedDate.addingTimeInterval(180)))
    }
}
