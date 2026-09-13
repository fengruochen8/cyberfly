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

        guard case let .loaded(restored) = try store.load() else {
            return XCTFail("Expected a saved snapshot")
        }
        XCTAssertEqual(restored, snapshot)
    }

    func testReadOnlySnapshotLoadPreservesAValidSharedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyReadOnlyTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FlySnapshotStore(fileURL: stateURL).save(.preview(now: fixedDate))

        let snapshot = try XCTUnwrap(FlySnapshotStore(fileURL: stateURL).loadReadOnly())

        XCTAssertEqual(snapshot.schemaVersion, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testReadOnlySnapshotLoadNeverQuarantinesInvalidSharedData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyReadOnlyCorruptTests-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{not-json".utf8).write(to: stateURL)

        XCTAssertThrowsError(try FlySnapshotStore(fileURL: stateURL).loadReadOnly())
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).count,
            1
        )
    }

    func testCorruptSnapshotIsQuarantinedBeforeANewSnapshotCanBeSaved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyCorruptSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("state.json")
        let corruptData = Data("{not-valid-json".utf8)
        try corruptData.write(to: stateURL)
        let store = FlySnapshotStore(fileURL: stateURL)

        guard case let .quarantined(quarantineURL, _) = try store.load() else {
            return XCTFail("Expected the corrupt snapshot to be quarantined")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantineURL), corruptData)
        try store.save(.preview(now: fixedDate))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineURL.path))
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

    func testActionCompetitionMaintainsAClearStableWinnerUnderSmallNoise() {
        var controller = EmbodiedNeuralController()
        let input = EmbodiedNeuralInput(
            energy: 0.9,
            fatigue: 0.52,
            arousal: 0.2,
            curiosity: 0.78
        )
        var outputs: [EmbodiedNeuralOutput] = []
        for index in 0..<160 {
            outputs.append(controller.step(
                input: input,
                deltaTime: 0.1,
                neuralNoise: index.isMultiple(of: 2) ? 0.18 : -0.18
            ))
        }
        let settled = Array(outputs.suffix(100))
        let transitions = zip(settled, settled.dropFirst()).filter {
            $0.behavior != $1.behavior
        }.count
        let minimumSettledConfidence = settled.map(\.actionConfidence).min() ?? 0

        XCTAssertLessThanOrEqual(transitions, 2)
        XCTAssertGreaterThan(minimumSettledConfidence, 0.05)
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

    func testFeedingBodyAndDopamineUseTheCurrentMotorCycle() {
        let simulation = FlySimulation(
            individualID: fixedID,
            seed: 7,
            initialEnergy: 0.12,
            configuration: .acceleratedTests
        )
        let food = FlyStimulus(
            foodOdor: 1,
            foodContact: 1,
            foodBearingRadians: 0,
            amberOdor: 1
        )

        let firstFeedingStep = simulation.step(
            deltaTime: 0.1,
            stimulus: food,
            now: fixedDate
        )

        XCTAssertEqual(firstFeedingStep.behavior, .feeding)
        XCTAssertGreaterThan(firstFeedingStep.feedingMotorDrive ?? 0, 0)
        XCTAssertGreaterThan(firstFeedingStep.energy, 0.12)
        XCTAssertEqual(
            firstFeedingStep.rewardDANActivity ?? -1,
            firstFeedingStep.feedingMotorDrive ?? -2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(simulation.learningMemoryRevision, 1)
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

    func testMemorySummaryDescribesTheCurrentCueInsteadOfAnotherStrongerMemory() {
        var circuit = MaleCNSLearningCircuit(individualID: fixedID)
        for _ in 0..<24 {
            _ = circuit.step(
                amberOdor: 1,
                berryOdor: 0,
                rewardSignal: 1,
                deltaTime: 1
            )
        }
        for _ in 0..<4 {
            _ = circuit.step(
                amberOdor: 0,
                berryOdor: 1,
                punishmentSignal: 1,
                deltaTime: 1
            )
        }

        let berry = circuit.step(amberOdor: 0, berryOdor: 1, deltaTime: 0.1)

        XCTAssertEqual(berry.currentCue, .berry)
        XCTAssertEqual(berry.strongestMemoryCue, .amber)
        XCTAssertTrue(berry.memorySummary.contains(FlyOdorCue.berry.displayName))
        XCTAssertFalse(berry.memorySummary.contains(FlyOdorCue.amber.displayName))
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
        var learningCircuit = MaleCNSLearningCircuit(individualID: fixedID)
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
        guard case let .loaded(restoredMemory) = try store.load(matching: circuit.individualID) else {
            return XCTFail("Expected saved learning memory")
        }
        var restored = MaleCNSLearningCircuit(memory: restoredMemory)
        let after = restored.step(amberOdor: 1, berryOdor: 0, deltaTime: 0.1)

        XCTAssertEqual(restored.memoryRevision, circuit.memoryRevision)
        XCTAssertEqual(after.currentLearnedValence, before.currentLearnedValence, accuracy: 0.0001)
        XCTAssertEqual(after.currentMemoryConfidence, before.currentMemoryConfidence, accuracy: 0.0001)
        XCTAssertEqual(restoredMemory.individualID, circuit.individualID)
    }

    func testLearningMemoryFromAnotherIndividualIsQuarantined() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyMemoryOwnerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let memoryURL = directory.appendingPathComponent("learning-memory.json")
        let store = MaleCNSLearningMemoryStore(fileURL: memoryURL)
        let circuit = MaleCNSLearningCircuit(individualID: fixedID)
        try store.save(circuit.exportMemory(now: fixedDate))
        let savedData = try Data(contentsOf: memoryURL)
        let otherID = UUID(uuidString: "7CB5663D-276A-465E-BB69-666D8A2C2096")!

        guard case let .quarantined(quarantineURL, reason) = try store.load(matching: otherID) else {
            return XCTFail("Expected another fly's memory to be quarantined")
        }

        XCTAssertTrue(reason.contains("记忆个体不匹配"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: memoryURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantineURL), savedData)
    }

    func testCorruptLearningMemoryIsQuarantined() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyCorruptMemoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let memoryURL = directory.appendingPathComponent("learning-memory.json")
        let corruptData = Data("[broken-learning-memory".utf8)
        try corruptData.write(to: memoryURL)
        let store = MaleCNSLearningMemoryStore(fileURL: memoryURL)

        guard case let .quarantined(quarantineURL, _) = try store.load(matching: fixedID) else {
            return XCTFail("Expected corrupt learning memory to be quarantined")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: memoryURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantineURL), corruptData)
    }

    func testLegacyLearningMemoryMigratesOnlyWithARestoredSnapshotIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyLegacyMemoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let memoryURL = directory.appendingPathComponent("learning-memory.json")
        let store = MaleCNSLearningMemoryStore(fileURL: memoryURL)
        let circuit = MaleCNSLearningCircuit(individualID: fixedID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let currentData = try encoder.encode(circuit.exportMemory(now: fixedDate))
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject["schemaVersion"] = 1
        legacyObject.removeValue(forKey: "individualID")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        try legacyData.write(to: memoryURL)

        guard case let .loaded(migrated) = try store.load(
            matching: fixedID,
            allowingLegacyMigration: true
        ) else {
            return XCTFail("Expected schema-one memory to migrate")
        }

        XCTAssertEqual(migrated.schemaVersion, MaleCNSLearningMemory.currentSchemaVersion)
        XCTAssertEqual(migrated.individualID, fixedID)

        try legacyData.write(to: memoryURL)
        guard case .quarantined = try store.load(
            matching: fixedID,
            allowingLegacyMigration: false
        ) else {
            return XCTFail("Expected ownerless legacy memory to be quarantined without a snapshot")
        }
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
            "memorySummary",
            "functionalSelf"
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
        XCTAssertNil(decoded.functionalSelf)
    }

    func testFunctionalSelfDistinguishesOwnMotionFromExternalDisplacement() {
        var model = FunctionalSelfModel(individualID: fixedID)
        let action = SelfActionCommand(
            behavior: .walking,
            actionNeuron: "ENG-ACT-WALK",
            actionConfidence: 0.7,
            forwardSpeed: 0.1,
            turnRateRadiansPerSecond: 0,
            wingDrive: 0,
            feedingDrive: 0,
            groomingDrive: 0,
            restDrive: 0
        )
        let before = selfBody(x: 0.4, y: 0.4, heading: 0)
        let prediction = model.predict(
            action: action,
            body: before,
            deltaTime: 0.1,
            expectedEnergyDelta: 0,
            expectedFatigueDelta: 0,
            expectedGroomingDelta: 0
        )
        let ownMotion = model.observe(
            prediction: prediction,
            before: before,
            after: selfBody(x: 0.41, y: 0.4, heading: 0),
            action: action,
            tick: 1,
            now: fixedDate
        )
        XCTAssertEqual(ownMotion.causalAttribution, .selfGenerated)
        XCTAssertLessThan(ownMotion.predictionError, 0.05)

        let secondBefore = selfBody(x: 0.41, y: 0.4, heading: 0)
        let secondPrediction = model.predict(
            action: action,
            body: secondBefore,
            deltaTime: 0.1,
            expectedEnergyDelta: 0,
            expectedFatigueDelta: 0,
            expectedGroomingDelta: 0
        )
        let displaced = model.observe(
            prediction: secondPrediction,
            before: secondBefore,
            after: selfBody(x: 0.59, y: 0.49, heading: .pi / 3),
            action: action,
            external: SelfExternalEvidence(
                displacementX: 0.17,
                displacementY: 0.09,
                headingDelta: .pi / 3
            ),
            tick: 2,
            now: fixedDate.addingTimeInterval(0.1)
        )
        XCTAssertEqual(displaced.causalAttribution, .external)
        XCTAssertGreaterThan(displaced.predictionError, ownMotion.predictionError)
        XCTAssertLessThan(displaced.agencyScore, ownMotion.agencyScore)
        XCTAssertTrue(displaced.explanation.contains("外界"))
        XCTAssertEqual(displaced.episodes.last?.attribution, .external)
    }

    func testFunctionalSelfSensorMaskRaisesUncertainty() {
        var model = FunctionalSelfModel(individualID: fixedID)
        let action = SelfActionCommand(
            behavior: .walking,
            actionNeuron: "ENG-ACT-WALK",
            actionConfidence: 0.8,
            forwardSpeed: 0.08,
            turnRateRadiansPerSecond: 0,
            wingDrive: 0,
            feedingDrive: 0,
            groomingDrive: 0,
            restDrive: 0
        )
        var body = selfBody(x: 0.3, y: 0.4, heading: 0)
        for tick in 1...12 {
            let prediction = model.predict(
                action: action,
                body: body,
                deltaTime: 0.1,
                expectedEnergyDelta: 0,
                expectedFatigueDelta: 0,
                expectedGroomingDelta: 0
            )
            let after = selfBody(x: body.positionX + 0.008, y: body.positionY, heading: 0)
            _ = model.observe(
                prediction: prediction,
                before: body,
                after: after,
                action: action,
                tick: UInt64(tick),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
            body = after
        }
        let reliableConfidence = model.state.confidence
        let prediction = model.predict(
            action: action,
            body: body,
            deltaTime: 0.1,
            expectedEnergyDelta: 0,
            expectedFatigueDelta: 0,
            expectedGroomingDelta: 0
        )
        let masked = model.observe(
            prediction: prediction,
            before: body,
            after: selfBody(x: body.positionX + 0.008, y: body.positionY, heading: 0),
            action: action,
            external: SelfExternalEvidence(sensorReliability: 0.1),
            tick: 13,
            now: fixedDate.addingTimeInterval(1.3)
        )

        XCTAssertLessThan(masked.confidence, reliableConfidence)
        XCTAssertGreaterThan(masked.uncertainty, 1 - reliableConfidence)
        XCTAssertTrue(masked.explanation.contains("感觉证据受限"))
    }

    func testFunctionalSelfRecognizesTouchTriggeredOwnResponseAsMixed() {
        var model = FunctionalSelfModel(individualID: fixedID)
        let action = SelfActionCommand(
            behavior: .startled,
            actionNeuron: "ENG-ACT-ESCAPE",
            actionConfidence: 0.9,
            forwardSpeed: 0.1,
            turnRateRadiansPerSecond: 0,
            wingDrive: 0.5,
            feedingDrive: 0,
            groomingDrive: 0,
            restDrive: 0
        )
        let before = selfBody(x: 0.4, y: 0.4, heading: 0)
        let prediction = model.predict(
            action: action,
            body: before,
            deltaTime: 0.1,
            expectedEnergyDelta: 0,
            expectedFatigueDelta: 0,
            expectedGroomingDelta: 0
        )
        let state = model.observe(
            prediction: prediction,
            before: before,
            after: selfBody(x: 0.41, y: 0.4, heading: 0),
            action: action,
            external: SelfExternalEvidence(touch: 1, visualMotion: 0.7),
            tick: 1,
            now: fixedDate
        )

        XCTAssertEqual(state.causalAttribution, .mixed)
        XCTAssertTrue(state.explanation.contains("外界触发"))
        XCTAssertGreaterThan(state.visualChannel, 0.6)
        XCTAssertGreaterThan(state.proprioceptiveChannel, 0.5)
    }

    func testFunctionalSelfDoesNotFloodEpisodesDuringSensorMask() {
        var model = FunctionalSelfModel(individualID: fixedID)
        let action = SelfActionCommand(
            behavior: .walking,
            actionNeuron: "ENG-ACT-WALK",
            actionConfidence: 0.8,
            forwardSpeed: 0.08,
            turnRateRadiansPerSecond: 0,
            wingDrive: 0,
            feedingDrive: 0,
            groomingDrive: 0,
            restDrive: 0
        )
        var body = selfBody(x: 0.2, y: 0.4, heading: 0)
        for tick in 1...30 {
            let prediction = model.predict(
                action: action,
                body: body,
                deltaTime: 0.1,
                expectedEnergyDelta: 0,
                expectedFatigueDelta: 0,
                expectedGroomingDelta: 0
            )
            let after = selfBody(x: body.positionX + 0.008, y: body.positionY, heading: 0)
            _ = model.observe(
                prediction: prediction,
                before: body,
                after: after,
                action: action,
                external: SelfExternalEvidence(sensorReliability: tick >= 3 ? 0.1 : 1),
                tick: UInt64(tick),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
            body = after
        }

        XCTAssertLessThanOrEqual(model.state.episodes.count, 3)
        XCTAssertEqual(
            model.state.episodes.filter { $0.summary.contains("感觉证据受限") }.count,
            1
        )
    }

    func testFunctionalSelfDebouncesAlternatingExternalTriggerEvidence() {
        var model = FunctionalSelfModel(individualID: fixedID)
        let action = SelfActionCommand(
            behavior: .startled,
            actionNeuron: "ENG-ACT-ESCAPE",
            actionConfidence: 0.8,
            forwardSpeed: 0.08,
            turnRateRadiansPerSecond: 0,
            wingDrive: 0.4,
            feedingDrive: 0,
            groomingDrive: 0,
            restDrive: 0
        )
        var body = selfBody(x: 0.2, y: 0.4, heading: 0)
        for tick in 1...40 {
            let prediction = model.predict(
                action: action,
                body: body,
                deltaTime: 0.1,
                expectedEnergyDelta: 0,
                expectedFatigueDelta: 0,
                expectedGroomingDelta: 0
            )
            let after = selfBody(x: body.positionX + 0.008, y: body.positionY, heading: 0)
            _ = model.observe(
                prediction: prediction,
                before: body,
                after: after,
                action: action,
                external: SelfExternalEvidence(touch: tick.isMultiple(of: 2) ? 1 : 0),
                tick: UInt64(tick),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
            body = after
        }

        XCTAssertLessThanOrEqual(model.state.episodes.count, 7)
        XCTAssertTrue(model.state.episodes.contains { $0.attribution == .mixed })
        XCTAssertTrue(model.state.episodes.contains { $0.attribution == .selfGenerated })
    }

    func testSelfUncertaintyFeedsBackIntoActionCompetition() throws {
        let confidentInput = EmbodiedNeuralInput(
            energy: 0.9,
            fatigue: 0.1,
            arousal: 0.45,
            curiosity: 0.82,
            novelty: 0.3,
            selfModelConfidence: 1,
            selfModelUncertainty: 0,
            selfPredictionError: 0
        )
        let uncertainInput = EmbodiedNeuralInput(
            energy: 0.9,
            fatigue: 0.1,
            arousal: 0.45,
            curiosity: 0.82,
            novelty: 0.3,
            selfModelConfidence: 0,
            selfModelUncertainty: 1,
            selfPredictionError: 1
        )
        var confidentController = EmbodiedNeuralController()
        var uncertainController = EmbodiedNeuralController()
        let confident = confidentController.step(
            input: confidentInput,
            deltaTime: 0.1,
            neuralNoise: 0
        )
        let uncertain = uncertainController.step(
            input: uncertainInput,
            deltaTime: 0.1,
            neuralNoise: 0
        )
        let exploringIndex = try XCTUnwrap(FlyBehavior.allCases.firstIndex(of: .exploring))
        let idleIndex = try XCTUnwrap(FlyBehavior.allCases.firstIndex(of: .idle))

        XCTAssertLessThan(
            uncertain.actionActivities[exploringIndex],
            confident.actionActivities[exploringIndex]
        )
        XCTAssertGreaterThan(
            uncertain.actionActivities[idleIndex],
            confident.actionActivities[idleIndex]
        )
    }

    func testFunctionalSelfLearnsReversedSteeringTransform() {
        var model = FunctionalSelfModel(individualID: fixedID)
        let action = SelfActionCommand(
            behavior: .exploring,
            actionNeuron: "ENG-ACT-EXPLORE",
            actionConfidence: 0.7,
            forwardSpeed: 0,
            turnRateRadiansPerSecond: 1,
            wingDrive: 0,
            feedingDrive: 0,
            groomingDrive: 0,
            restDrive: 0
        )
        var heading = 0.0
        var firstError = 0.0
        var latest = model.state
        for tick in 1...32 {
            let before = selfBody(x: 0.5, y: 0.5, heading: heading)
            let prediction = model.predict(
                action: action,
                body: before,
                deltaTime: 0.1,
                expectedEnergyDelta: 0,
                expectedFatigueDelta: 0,
                expectedGroomingDelta: 0
            )
            heading -= 0.1
            latest = model.observe(
                prediction: prediction,
                before: before,
                after: selfBody(x: 0.5, y: 0.5, heading: heading),
                action: action,
                tick: UInt64(tick),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
            if tick == 1 { firstError = latest.predictionError }
        }

        XCTAssertLessThan(latest.learnedTurnGain, -0.85)
        XCTAssertLessThan(latest.predictionError, firstError * 0.2)
        XCTAssertEqual(latest.causalAttribution, .selfGenerated)
    }

    func testFunctionalSelfEpisodesPersistAcrossSimulationRestart() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 202)
        _ = simulation.step(deltaTime: 0.1, stimulus: .quiet, now: fixedDate)
        simulation.applyExternalDisplacement(
            deltaX: 0.15,
            deltaY: 0.08,
            headingDelta: .pi / 4
        )
        let saved = simulation.step(
            deltaTime: 0.1,
            stimulus: .quiet,
            now: fixedDate.addingTimeInterval(0.1)
        )
        let savedSelf = try XCTUnwrap(saved.functionalSelf)
        let restored = FlySimulation(restoring: saved, seed: 203)

        XCTAssertEqual(restored.individualID, fixedID)
        XCTAssertEqual(restored.functionalSelfState.episodeRevision, savedSelf.episodeRevision)
        XCTAssertEqual(restored.functionalSelfState.episodes, savedSelf.episodes)
        XCTAssertEqual(restored.functionalSelfState.episodes.last?.attribution, .external)
    }

    func testFunctionalSelfAblationRemovesAgencyAndAutobiographicalMemory() {
        let ablated = FlySimulation(
            individualID: fixedID,
            seed: 404,
            functionalSelfEnabled: false
        )
        ablated.applyExternalDisplacement(deltaX: 0.15, deltaY: 0.08)
        let snapshot = ablated.step(
            deltaTime: 0.1,
            stimulus: FlyStimulus(touch: 1),
            now: fixedDate
        )
        let selfState = snapshot.functionalSelf

        XCTAssertEqual(selfState?.enabled, false)
        XCTAssertEqual(selfState?.agencyScore, 0)
        XCTAssertEqual(selfState?.confidence, 0)
        XCTAssertEqual(selfState?.episodes, [])
        XCTAssertEqual(snapshot.modelFidelity, .embodiedNeural)
    }

    func testCounterfactualPlannerEvaluatesMultipleFuturesInTheLiveLoop() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 601)
        let snapshot = simulation.step(
            deltaTime: 0.1,
            stimulus: FlyStimulus(novelty: 0.45),
            now: fixedDate
        )
        let counterfactual = try XCTUnwrap(snapshot.counterfactualSelf)

        XCTAssertEqual(snapshot.schemaVersion, 9)
        XCTAssertEqual(snapshot.modelFidelity, .socialSelfCognition)
        XCTAssertEqual(counterfactual.candidates.count, 9)
        XCTAssertTrue(counterfactual.candidates.contains {
            $0.behavior == counterfactual.selectedBehavior
        })
        XCTAssertGreaterThan(counterfactual.candidates.map(\.expectedUtility).max() ?? -1, 0)
    }

    func testHiddenWindIsInferredWithoutGivingTheSelfModelTheAnswer() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 602)
        for tick in 1...12 {
            _ = simulation.step(
                deltaTime: 0.1,
                stimulus: FlyStimulus(novelty: 0.3),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
        }
        simulation.applyExternalDisplacement(
            deltaX: 0.16,
            deltaY: 0.08,
            headingDelta: .pi / 3,
            revealToSelfModel: false
        )
        let snapshot = simulation.step(
            deltaTime: 0.1,
            stimulus: .quiet,
            now: fixedDate.addingTimeInterval(1.3)
        )
        let counterfactual = try XCTUnwrap(snapshot.counterfactualSelf)

        XCTAssertEqual(snapshot.functionalSelf?.causalAttribution, .external)
        XCTAssertGreaterThan(counterfactual.worldHypothesisProbability, 0.5)
        XCTAssertGreaterThan(counterfactual.worldHypothesisProbability, counterfactual.selfHypothesisProbability)
        XCTAssertEqual(counterfactual.blindExternalEventCount, 1)
        XCTAssertTrue(counterfactual.explanation.contains("未读取实验标签"))
    }

    func testLowReliabilityProducesAnEpistemicProbePolicy() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 603)
        var snapshot = simulation.step(deltaTime: 0.1, now: fixedDate)
        for tick in 2...6 {
            snapshot = simulation.step(
                deltaTime: 0.1,
                stimulus: FlyStimulus(novelty: 0.04, sensorReliability: 0.08),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
        }
        let counterfactual = try XCTUnwrap(snapshot.counterfactualSelf)

        XCTAssertTrue(counterfactual.shouldProbe)
        XCTAssertGreaterThan(counterfactual.epistemicDrive, 0.5)
        XCTAssertEqual(counterfactual.selectedBehavior, .exploring)
    }

    func testCounterfactualPlanChangesActionPopulationActivity() throws {
        let base = EmbodiedNeuralInput(
            energy: 0.8,
            fatigue: 0.3,
            arousal: 0.2,
            curiosity: 0.35
        )
        let planned = EmbodiedNeuralInput(
            energy: 0.8,
            fatigue: 0.3,
            arousal: 0.2,
            curiosity: 0.35,
            plannedBehavior: .resting,
            planningConfidence: 1
        )
        var baseController = EmbodiedNeuralController()
        var plannedController = EmbodiedNeuralController()
        let baseOutput = baseController.step(input: base, deltaTime: 0.1, neuralNoise: 0)
        let plannedOutput = plannedController.step(input: planned, deltaTime: 0.1, neuralNoise: 0)
        let resting = try XCTUnwrap(FlyBehavior.allCases.firstIndex(of: .resting))

        XCTAssertGreaterThan(
            plannedOutput.actionActivities[resting],
            baseOutput.actionActivities[resting]
        )
        XCTAssertEqual(EmbodiedNeuralController.totalNeuronCount, 49)
    }

    func testUrgentThreatInterruptsButDoesNotEraseTheLongTermGoal() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 604)
        _ = simulation.step(deltaTime: 0.1, now: fixedDate)
        var snapshot = simulation.step(
            deltaTime: 0.1,
            stimulus: FlyStimulus(threat: 0.95),
            now: fixedDate.addingTimeInterval(0.1)
        )
        XCTAssertEqual(snapshot.semanticSelf?.activeGoal, .avoidThreat)

        for tick in 3...12 {
            snapshot = simulation.step(
                deltaTime: 0.1,
                stimulus: .quiet,
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
        }
        let semantic = try XCTUnwrap(snapshot.semanticSelf)
        XCTAssertEqual(semantic.activeGoal, .avoidThreat)
        XCTAssertEqual(semantic.goalSinceTick, 2)
    }

    func testSemanticSelfConsolidatesExperiencesIntoStableBeliefs() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 605)
        var snapshot = simulation.step(deltaTime: 0.1, now: fixedDate)
        for tick in 2...35 {
            snapshot = simulation.step(
                deltaTime: 0.1,
                stimulus: FlyStimulus(novelty: 0.25),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
        }
        let semantic = try XCTUnwrap(snapshot.semanticSelf)

        XCTAssertGreaterThanOrEqual(semantic.consolidationCount, 3)
        XCTAssertEqual(Set(semantic.beliefs.map(\.key)), Set([
            "motor-control", "sensory-trust", "external-volatility", "social-contingency"
        ]))
        XCTAssertTrue(semantic.beliefs.allSatisfy { $0.evidenceCount >= 3 })
    }

    func testSemanticAndMetacognitiveStatesPersistAcrossRestart() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 606)
        var saved = simulation.step(deltaTime: 0.1, now: fixedDate)
        for tick in 2...30 {
            saved = simulation.step(
                deltaTime: 0.1,
                stimulus: FlyStimulus(novelty: 0.35),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
        }
        let restored = FlySimulation(restoring: saved, seed: 607)

        XCTAssertEqual(restored.counterfactualSelfState.calibrationSampleCount, saved.counterfactualSelf?.calibrationSampleCount)
        XCTAssertEqual(restored.semanticSelfState.beliefs, saved.semanticSelf?.beliefs)
        XCTAssertEqual(restored.semanticSelfState.activeGoal, saved.semanticSelf?.activeGoal)
        XCTAssertEqual(restored.semanticSelfState.consolidationCount, saved.semanticSelf?.consolidationCount)
    }

    func testIndependentOtherIsSeparatedFromTheSelf() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 608)
        var snapshot = simulation.step(deltaTime: 0.1, now: fixedDate)
        for tick in 2...30 {
            snapshot = simulation.step(
                deltaTime: 0.1,
                stimulus: FlyStimulus(
                    novelty: 0.25,
                    otherAgentID: "OTHER-BETA",
                    otherAgentPresence: 1,
                    otherAgentMotion: 1,
                    otherAgentContingency: 0.20,
                    otherAgentThreat: 0.05
                ),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
        }
        let social = try XCTUnwrap(snapshot.socialSelf)

        XCTAssertTrue(social.otherPresent)
        XCTAssertEqual(social.trackedOtherID, "OTHER-BETA")
        XCTAssertGreaterThan(social.otherAgencyProbability, 0.5)
        XCTAssertGreaterThan(social.selfOtherSeparation, 0.6)
        XCTAssertEqual(social.attribution, .otherAgent)
    }

    func testContingentOtherProducesJointActionAttribution() throws {
        let simulation = FlySimulation(individualID: fixedID, seed: 609)
        var snapshot = simulation.step(deltaTime: 0.1, now: fixedDate)
        for tick in 2...20 {
            snapshot = simulation.step(
                deltaTime: 0.1,
                stimulus: FlyStimulus(
                    novelty: 0.7,
                    otherAgentID: "OTHER-ALPHA",
                    otherAgentPresence: 1,
                    otherAgentMotion: 0.9,
                    otherAgentContingency: 0.95,
                    otherAgentThreat: 0.02
                ),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
        }
        let social = try XCTUnwrap(snapshot.socialSelf)

        XCTAssertGreaterThan(social.otherAgencyProbability, 0.75)
        XCTAssertGreaterThan(social.jointActionProbability, 0.48)
        XCTAssertEqual(social.attribution, .joint)
        XCTAssertGreaterThan(social.socialEpisodeCount, 0)
    }

    func testSocialModelAblationRemovesOtherAgentInference() throws {
        let simulation = FlySimulation(
            individualID: fixedID,
            seed: 610,
            socialSelfEnabled: false
        )
        let snapshot = simulation.step(
            deltaTime: 0.1,
            stimulus: FlyStimulus(
                otherAgentID: "OTHER-ALPHA",
                otherAgentPresence: 1,
                otherAgentMotion: 1,
                otherAgentContingency: 1
            ),
            now: fixedDate
        )
        let social = try XCTUnwrap(snapshot.socialSelf)

        XCTAssertFalse(social.enabled)
        XCTAssertFalse(social.otherPresent)
        XCTAssertEqual(social.otherAgencyProbability, 0)
        XCTAssertNil(social.trackedOtherID)
        XCTAssertEqual(snapshot.modelFidelity, .semanticSelfCognition)
    }

    func testCognitiveStatesAreResetForAnotherIndividual() {
        let original = FlySimulation(individualID: fixedID, seed: 611)
        var snapshot = original.step(deltaTime: 0.1, now: fixedDate)
        for tick in 2...12 {
            snapshot = original.step(
                deltaTime: 0.1,
                stimulus: FlyStimulus(novelty: 0.2),
                now: fixedDate.addingTimeInterval(Double(tick) * 0.1)
            )
        }
        let anotherID = UUID(uuidString: "3E1D1951-12C7-4CA9-AFC5-A4F9CFA54451")!
        let another = FlySimulation(
            individualID: anotherID,
            seed: 612,
            counterfactualSelfState: snapshot.counterfactualSelf,
            semanticSelfState: snapshot.semanticSelf,
            socialSelfState: snapshot.socialSelf
        )
        XCTAssertEqual(another.counterfactualSelfState.individualID, anotherID)
        XCTAssertEqual(another.counterfactualSelfState.calibrationSampleCount, 0)
        XCTAssertEqual(another.semanticSelfState.individualID, anotherID)
        XCTAssertTrue(another.semanticSelfState.beliefs.isEmpty)
        XCTAssertEqual(another.socialSelfState.individualID, anotherID)
    }

    private func selfBody(
        x: Double,
        y: Double,
        heading: Double
    ) -> SelfBodyObservation {
        SelfBodyObservation(
            positionX: x,
            positionY: y,
            headingRadians: heading,
            energy: 0.8,
            fatigue: 0.2,
            groomingNeed: 0.1,
            lifeState: .active
        )
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
        XCTAssertEqual(snapshot.modelFidelity, .socialSelfCognition)
        XCTAssertFalse(snapshot.isStale(relativeTo: fixedDate.addingTimeInterval(60)))
        XCTAssertTrue(snapshot.isStale(relativeTo: fixedDate.addingTimeInterval(180)))
    }

    func testFullCNSGraphLoadsEveryTracedNodeAndObservedEdge() throws {
        let graph = try FullCNSGraph.bundled()

        XCTAssertEqual(graph.manifest.dataset, "male-cns:v1.0")
        XCTAssertEqual(graph.manifest.graphSha256, FullCNSGraph.pinnedGraphSHA256)
        XCTAssertEqual(graph.nodeCount, 165_122)
        XCTAssertEqual(graph.edgeCount, 25_563_197)
        XCTAssertEqual(graph.manifest.synapseWeightSum, 124_025_046)
        XCTAssertEqual(graph.indices(with: .motor).count, 815)
        XCTAssertEqual(graph.indices(with: .centralComplex).count, 2_950)
        XCTAssertEqual(graph.indices(with: .dopaminergic).count, 392)
        XCTAssertLessThan(graph.node(at: 0).bodyID, graph.node(at: graph.nodeCount - 1).bodyID)
    }

    func testFullCNSGraphPassesDeepBidirectionalValidation() throws {
        let report = try FullCNSGraph.bundled().validateDeep()

        XCTAssertTrue(report.isExact)
        XCTAssertEqual(report.nodeCount, 165_122)
        XCTAssertEqual(report.edgeCount, 25_563_197)
        XCTAssertEqual(report.synapseWeightSum, 124_025_046)
        XCTAssertEqual(report.incomingSynapseWeightSum, report.synapseWeightSum)
        XCTAssertTrue(report.fileChecksumsMatch)
        XCTAssertTrue(report.graphChecksumMatchesPinnedArtifact)
        XCTAssertGreaterThan(report.maximumOutDegree, 0)
        XCTAssertGreaterThan(report.maximumInDegree, 0)
    }

    func testFullCNSRuntimeUpdatesTheEntireStateAndPropagatesObservedEdges() throws {
        let runtime = FullCNSRuntime(graph: try FullCNSGraph.bundled())
        var result = FullCNSRuntimeMetrics.idle(graph: runtime.graph)
        let input = FullCNSSensoryInput(
            leftVisualMotion: 0.8,
            rightVisualMotion: 0.3,
            odor: 0.7,
            taste: 0.5,
            touch: 0.6,
            proprioception: 0.4,
            hunger: 0.7,
            reward: 0.5
        )
        for _ in 0..<10 {
            result = runtime.step(deltaTime: 0.1, input: input)
        }
        XCTAssertEqual(result.nodeCount, 165_122)
        XCTAssertEqual(result.edgeCount, 25_563_197)
        XCTAssertGreaterThan(result.spikeCount, 0)
        XCTAssertGreaterThan(result.edgeEventCount, 0)
        XCTAssertGreaterThan(result.activeNeuronCount, 0)
        XCTAssertGreaterThan(result.sensoryActivity, 0)
        XCTAssertGreaterThan(result.dopamineLevel, 0)
        XCTAssertGreaterThan(result.realTimeFactor, 0)
        XCTAssertFalse(result.eventBudgetSaturated)
    }

    func testFullCNSRuntimeIsIntegratedIntoTheEmbodiedSimulationSnapshot() throws {
        let runtime = FullCNSRuntime(graph: try FullCNSGraph.bundled())
        let simulation = FlySimulation(
            individualID: fixedID,
            seed: 81,
            initialEnergy: 0.2,
            fullCNSRuntime: runtime
        )
        let snapshot = simulation.step(
            deltaTime: 0.1,
            stimulus: FlyStimulus(
                foodOdor: 0.8,
                foodContact: 0.7,
                foodBearingRadians: 0.2,
                amberOdor: 0.8,
                threat: 0.4,
                visualMotionBearingRadians: 0.7,
                novelty: 0.6
            ),
            now: fixedDate
        )

        XCTAssertEqual(snapshot.modelFidelity, .socialSelfCognition)
        XCTAssertEqual(snapshot.wholeCNSDataset, "male-cns:v1.0")
        XCTAssertEqual(snapshot.wholeCNSNodeCount, 165_122)
        XCTAssertEqual(snapshot.wholeCNSEdgeCount, 25_563_197)
        XCTAssertGreaterThan(snapshot.wholeCNSSpikeCount ?? 0, 0)
        XCTAssertGreaterThan(snapshot.wholeCNSEdgeEventCount ?? 0, 0)
        XCTAssertFalse(snapshot.wholeCNSEventBudgetSaturated ?? true)
        XCTAssertEqual(
            snapshot.controllerNeuronCount,
            EmbodiedNeuralController.totalNeuronCount
        )
        XCTAssertTrue(snapshot.reason.contains("MaleCNS 全 CNS"))
    }

    func testFullCNSDynamicStatePersistsAndRestoresForTheSameIndividual() throws {
        let graph = try FullCNSGraph.bundled()
        let runtime = FullCNSRuntime(graph: graph)
        _ = runtime.step(
            deltaTime: 0.1,
            input: FullCNSSensoryInput(
                leftVisualMotion: 0.8,
                odor: 0.7,
                touch: 0.5,
                reward: 0.6
            )
        )
        let before = runtime.exportPersistentState(individualID: fixedID, now: fixedDate)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyFullCNSStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FullCNSStateStore(
            fileURL: directory.appendingPathComponent("full-cns-state.plist")
        )
        try store.save(before)

        guard case let .loaded(saved) = try store.load(
            matching: fixedID,
            graphSHA256: graph.manifest.graphSha256,
            nodeCount: graph.nodeCount
        ) else {
            return XCTFail("Expected a saved full-CNS state")
        }
        let restoredRuntime = FullCNSRuntime(graph: graph)
        try restoredRuntime.restorePersistentState(saved)
        let after = restoredRuntime.exportPersistentState(individualID: fixedID, now: fixedDate)

        XCTAssertEqual(after, before)
    }

    func testCorruptFullCNSStateIsQuarantined() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CyberFlyCorruptFullCNSStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("full-cns-state.plist")
        let corruptData = Data("not-a-state".utf8)
        try corruptData.write(to: stateURL)
        let store = FullCNSStateStore(fileURL: stateURL)

        guard case let .quarantined(quarantineURL, _) = try store.load(
            matching: fixedID,
            graphSHA256: "graph",
            nodeCount: 1
        ) else {
            return XCTFail("Expected the corrupt full-CNS state to be quarantined")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantineURL), corruptData)
    }

    func testDecodableOutOfRangeFullCNSStateIsQuarantined() throws {
        let graph = try FullCNSGraph.bundled()
        let runtime = FullCNSRuntime(graph: graph)
        let state = runtime.exportPersistentState(individualID: fixedID, now: fixedDate)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CyberFlyInvalidFullCNSStateTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("full-cns-state.plist")
        let store = FullCNSStateStore(fileURL: stateURL)
        try store.save(state)

        let encoded = try Data(contentsOf: stateURL)
        let decoded = try PropertyListSerialization.propertyList(
            from: encoded,
            options: [],
            format: nil
        )
        var propertyList = try XCTUnwrap(decoded as? [String: Any])
        propertyList["globalCursor"] = graph.nodeCount
        let invalidData = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )
        try invalidData.write(to: stateURL, options: .atomic)

        guard case let .quarantined(quarantineURL, reason) = try store.load(
            matching: fixedID,
            graphSHA256: graph.manifest.graphSha256,
            nodeCount: graph.nodeCount
        ) else {
            return XCTFail("Expected the invalid full-CNS state to be quarantined")
        }
        XCTAssertTrue(reason.contains("非法数值"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantineURL), invalidData)
    }

    func testDNg13SilencingAblatesTheFullCNSVisualSteeringReadout() throws {
        let graph = try FullCNSGraph.bundled()
        let input = FullCNSSensoryInput(
            leftVisualMotion: 1,
            rightVisualMotion: 0.05,
            touch: 0.2
        )
        let control = FullCNSRuntime(graph: graph)
        var controlBias = 0.0
        for _ in 0..<8 {
            controlBias = max(
                controlBias,
                abs(control.step(deltaTime: 0.1, input: input).turnBias)
            )
        }

        let ablated = FullCNSRuntime(graph: graph)
        XCTAssertEqual(ablated.setSilenced(bodyIDs: [11_074, 512_006]), 2)
        var ablatedBias = 0.0
        var ablatedMetrics = FullCNSRuntimeMetrics.idle(graph: graph)
        for _ in 0..<8 {
            ablatedMetrics = ablated.step(deltaTime: 0.1, input: input)
            ablatedBias = max(ablatedBias, abs(ablatedMetrics.turnBias))
        }

        XCTAssertGreaterThan(controlBias, 0.02)
        XCTAssertEqual(ablatedBias, 0, accuracy: 0.000_001)
        XCTAssertEqual(ablatedMetrics.silencedNeuronCount, 2)
        XCTAssertGreaterThan(ablatedMetrics.edgeEventCount, 0)
    }

    func testNeuronInspectionFindsAnnotatedDNg13WithLiveState() throws {
        let runtime = FullCNSRuntime(graph: try FullCNSGraph.bundled())
        _ = runtime.step(
            deltaTime: 0.1,
            input: FullCNSSensoryInput(
                leftVisualMotion: 1,
                rightVisualMotion: 0.05,
                touch: 0.2
            )
        )

        let matches = runtime.inspectNeurons(matching: FullCNSNeuronQuery(
            bodyIDText: "DNg13",
            role: .descending,
            limit: 10
        ))

        XCTAssertEqual(Set(matches.map(\.bodyID)), Set([UInt64(11_074), UInt64(512_006)]))
        let left = try XCTUnwrap(runtime.inspectNeuron(bodyID: 11_074))
        XCTAssertEqual(left.annotationType, "DNg13")
        XCTAssertEqual(left.annotationInstance, "DNg13_L")
        XCTAssertTrue(left.roles.contains(.descending))
        XCTAssertGreaterThan(left.outgoingEdgeCount, 0)
        XCTAssertGreaterThan(left.incomingEdgeCount, 0)
        XCTAssertTrue(left.membranePotential.isFinite)
        XCTAssertTrue(left.activity.isFinite)
        XCTAssertTrue(left.presynapticEligibility.isFinite)
    }

    func testDNg13ExperimentRunnerProducesPairedCausalResult() throws {
        let graph = try FullCNSGraph.bundled()
        let result = try FullCNSExperimentRunner.run(
            graph: graph,
            definition: .dng13VisualSteering,
            now: fixedDate
        )

        XCTAssertEqual(result.createdAt, fixedDate)
        XCTAssertEqual(result.dataset, "male-cns:v1.0")
        XCTAssertEqual(result.graphSHA256, FullCNSGraph.pinnedGraphSHA256)
        XCTAssertEqual(result.resolvedTargetCount, 2)
        XCTAssertEqual(result.samples.count, 8)
        XCTAssertEqual(result.expectationPassed, true)
        XCTAssertGreaterThan(result.controlPeakAbsoluteTurnBias, 0.02)
        XCTAssertEqual(result.interventionPeakAbsoluteTurnBias, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(result.controlTotalEdgeEvents, 0)
        XCTAssertGreaterThan(result.interventionTotalEdgeEvents, 0)
    }
}
