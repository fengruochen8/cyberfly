import AppKit
import Combine
import CyberFlyCore
import CyberFlySimulation
import Foundation
import WidgetKit

private final class RuntimeSimulationWorker: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.dadudu.CyberFly.simulation",
        qos: .userInitiated
    )
    private let simulation: FlySimulation
    private let snapshotStore: FlySnapshotStore
    private let learningMemoryStore: MaleCNSLearningMemoryStore
    private let fullCNSStateStore: FullCNSStateStore
    private let persistenceEnabled: Bool
    private var fullCNSPersistenceEnabled: Bool
    private var lastSavedLearningRevision: UInt64
    private var lastFullCNSStateSaveAt = Date.distantPast
    private var latestSnapshot: FlyStateSnapshot

    let manifest: FullCNSManifest?

    init(
        simulation: FlySimulation,
        initialSnapshot: FlyStateSnapshot,
        snapshotStore: FlySnapshotStore,
        learningMemoryStore: MaleCNSLearningMemoryStore,
        fullCNSStateStore: FullCNSStateStore,
        persistenceEnabled: Bool,
        fullCNSPersistenceEnabled: Bool
    ) {
        self.simulation = simulation
        self.latestSnapshot = initialSnapshot
        self.snapshotStore = snapshotStore
        self.learningMemoryStore = learningMemoryStore
        self.fullCNSStateStore = fullCNSStateStore
        self.persistenceEnabled = persistenceEnabled
        self.fullCNSPersistenceEnabled = fullCNSPersistenceEnabled
        self.lastSavedLearningRevision = simulation.learningMemoryRevision
        self.manifest = simulation.fullCNSManifest
    }

    func step(
        deltaTime: TimeInterval,
        stimulus: FlyStimulus,
        now: Date,
        completion: @escaping @Sendable (FlyStateSnapshot) -> Void
    ) {
        queue.async { [self] in
            let snapshot = simulation.step(
                deltaTime: deltaTime,
                stimulus: stimulus,
                now: now
            )
            latestSnapshot = snapshot
            completion(snapshot)
        }
    }

    func addContamination(_ amount: Double) {
        queue.async { [simulation] in
            simulation.addContamination(amount)
        }
    }

    func revive() {
        queue.async { [simulation] in
            simulation.revive()
        }
    }

    func applyExternalDisplacement(
        deltaX: Double,
        deltaY: Double,
        headingDelta: Double,
        revealToSelfModel: Bool = true
    ) {
        queue.async { [simulation] in
            simulation.applyExternalDisplacement(
                deltaX: deltaX,
                deltaY: deltaY,
                headingDelta: headingDelta,
                revealToSelfModel: revealToSelfModel
            )
        }
    }

    func setMotorControlTransform(forwardScale: Double, turnScale: Double) {
        queue.async { [simulation] in
            simulation.setMotorControlTransform(
                forwardScale: forwardScale,
                turnScale: turnScale
            )
        }
    }

    func inspectNeurons(
        matching query: FullCNSNeuronQuery
    ) -> [FullCNSNeuronObservation] {
        queue.sync {
            simulation.inspectFullCNSNeurons(matching: query)
        }
    }

    func inspectNeuron(bodyID: UInt64) -> FullCNSNeuronObservation? {
        queue.sync {
            simulation.inspectFullCNSNeuron(bodyID: bodyID)
        }
    }

    func persistAsync(force: Bool, reloadWidget: Bool) {
        queue.async { [self] in
            persist(force: force, reloadWidget: reloadWidget)
        }
    }

    func stopAndSave() {
        queue.sync { [self] in
            persist(force: true, reloadWidget: true)
        }
    }

    private func persist(force: Bool, reloadWidget: Bool) {
        guard persistenceEnabled else { return }
        do {
            try snapshotStore.save(latestSnapshot)
            if force || simulation.learningMemoryRevision != lastSavedLearningRevision {
                try learningMemoryStore.save(simulation.exportLearningMemory())
                lastSavedLearningRevision = simulation.learningMemoryRevision
            }
        } catch {
            NSLog("CyberFly snapshot save failed: %@", error.localizedDescription)
            return
        }

        if fullCNSPersistenceEnabled,
           force || Date().timeIntervalSince(lastFullCNSStateSaveAt) >= 30,
           let state = simulation.exportFullCNSPersistentState() {
            do {
                try fullCNSStateStore.save(state)
                lastFullCNSStateSaveAt = Date()
            } catch {
                fullCNSPersistenceEnabled = false
                NSLog("CyberFly full-CNS state save disabled: %@", error.localizedDescription)
            }
        }

        if reloadWidget {
            WidgetCenter.shared.reloadTimelines(ofKind: FlyWidgetKind.value)
        }
    }
}

@MainActor
final class RuntimeController: ObservableObject {
    @Published private(set) var snapshot: FlyStateSnapshot
    @Published private(set) var isPaused = false
    @Published private(set) var food: FoodResource?

    private let worker: RuntimeSimulationWorker
    private var timer: Timer?
    private var advanceInFlight = false
    private var lastStepAt = Date()
    private var lastSaveAt = Date.distantPast
    private var widgetRefreshPolicy = WidgetRefreshPolicy()
    private var previousMouseLocation = NSEvent.mouseLocation
    private var touchPulse = 0.0
    private var contaminationPulse = 0.0
    private var sensorMaskRemaining = 0.0
    private var reversedSteeringRemaining = 0.0
    private var goalConflictRemaining = 0.0
    private var otherAgentRemaining = 0.0
    private var otherAgentIsContingent = true

    init(
        simulation: FlySimulation? = nil,
        snapshotStore: FlySnapshotStore = FlySnapshotStore(),
        learningMemoryStore: MaleCNSLearningMemoryStore? = nil,
        fullCNSStateStore: FullCNSStateStore? = nil
    ) {
        let resolvedMemoryStore = learningMemoryStore
            ?? MaleCNSLearningMemoryStore.nextToSnapshot(snapshotStore.snapshotURL)
        let resolvedFullCNSStateStore = fullCNSStateStore
            ?? FullCNSStateStore.nextToSnapshot(snapshotStore.snapshotURL)
        let resolvedSimulation: FlySimulation
        var canPersist = true
        var canPersistFullCNS = true
        if let simulation {
            resolvedSimulation = simulation
        } else {
            let fullCNSRuntime: FullCNSRuntime?
            do {
                fullCNSRuntime = FullCNSRuntime(graph: try FullCNSGraph.bundled())
            } catch {
                fullCNSRuntime = nil
                NSLog("CyberFly full-CNS runtime unavailable: %@", error.localizedDescription)
            }
            var savedSnapshot: FlyStateSnapshot?
            do {
                switch try snapshotStore.load() {
                case .missing:
                    break
                case let .loaded(snapshot):
                    savedSnapshot = snapshot
                case let .quarantined(fileURL, reason):
                    NSLog(
                        "CyberFly quarantined unreadable snapshot at %@: %@",
                        fileURL.path,
                        reason
                    )
                }
            } catch {
                canPersist = false
                NSLog("CyberFly snapshot recovery blocked: %@", error.localizedDescription)
            }

            let individualID = savedSnapshot?.individualID ?? UUID()
            if canPersist, let fullCNSRuntime {
                do {
                    switch try resolvedFullCNSStateStore.load(
                        matching: individualID,
                        graphSHA256: fullCNSRuntime.graph.manifest.graphSha256,
                        nodeCount: fullCNSRuntime.graph.nodeCount
                    ) {
                    case .missing:
                        break
                    case let .loaded(state):
                        try fullCNSRuntime.restorePersistentState(state)
                    case let .quarantined(fileURL, reason):
                        NSLog(
                            "CyberFly quarantined incompatible full-CNS state at %@: %@",
                            fileURL.path,
                            reason
                        )
                    }
                } catch {
                    canPersistFullCNS = false
                    NSLog("CyberFly full-CNS state recovery blocked: %@", error.localizedDescription)
                }
            } else if !canPersist {
                canPersistFullCNS = false
            }
            var learningMemory: MaleCNSLearningMemory?
            if canPersist {
                do {
                    switch try resolvedMemoryStore.load(
                        matching: individualID,
                        allowingLegacyMigration: savedSnapshot != nil
                    ) {
                    case .missing:
                        break
                    case let .loaded(memory):
                        learningMemory = memory
                    case let .quarantined(fileURL, reason):
                        NSLog(
                            "CyberFly quarantined incompatible learning memory at %@: %@",
                            fileURL.path,
                            reason
                        )
                    }
                } catch {
                    canPersist = false
                    NSLog("CyberFly memory recovery blocked: %@", error.localizedDescription)
                }
            }

            if let savedSnapshot {
                resolvedSimulation = FlySimulation(
                    restoring: savedSnapshot,
                    learningMemory: learningMemory,
                    fullCNSRuntime: fullCNSRuntime
                )
            } else {
                resolvedSimulation = FlySimulation(
                    individualID: individualID,
                    learningMemory: learningMemory,
                    fullCNSRuntime: fullCNSRuntime
                )
            }
        }
        let initialSnapshot = resolvedSimulation.step(deltaTime: 0.001)
        self.snapshot = initialSnapshot
        self.worker = RuntimeSimulationWorker(
            simulation: resolvedSimulation,
            initialSnapshot: initialSnapshot,
            snapshotStore: snapshotStore,
            learningMemoryStore: resolvedMemoryStore,
            fullCNSStateStore: resolvedFullCNSStateStore,
            persistenceEnabled: canPersist,
            fullCNSPersistenceEnabled: canPersist && canPersistFullCNS
        )
    }

    func start() {
        guard timer == nil else { return }
        lastStepAt = Date()
        persistSnapshot(forceWidgetRefresh: true)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopAndSave() {
        timer?.invalidate()
        timer = nil
        worker.stopAndSave()
    }

    func togglePause() {
        isPaused.toggle()
        lastStepAt = Date()
    }

    func placeFood(odorCue: FlyOdorCue = .amber) {
        let position: CGPoint
        if snapshot.lifeState == .active {
            position = CGPoint(
                x: Double.random(in: 0.12...0.88),
                y: Double.random(in: 0.12...0.78)
            )
        } else {
            position = CGPoint(x: snapshot.positionX, y: snapshot.positionY)
        }
        food = FoodResource(
            odorCue: odorCue,
            positionX: position.x,
            positionY: position.y,
            placedAt: Date()
        )
    }

    func removeFood() {
        food = nil
    }

    func touchFly() {
        touchPulse = 1
    }

    func addDust() {
        contaminationPulse = 1
        worker.addContamination(0.42)
    }

    func displaceFlyExternally() {
        let deltaX = snapshot.positionX < 0.70 ? 0.16 : -0.16
        let deltaY = snapshot.positionY < 0.72 ? 0.09 : -0.09
        worker.applyExternalDisplacement(
            deltaX: deltaX,
            deltaY: deltaY,
            headingDelta: .pi / 3
        )
        advance(force: true)
    }

    func maskSenses() {
        sensorMaskRemaining = 4
        advance(force: true)
    }

    func reverseSteering() {
        reversedSteeringRemaining = 5
        worker.setMotorControlTransform(forwardScale: 1, turnScale: -1)
        advance(force: true)
    }

    func applyHiddenWind() {
        let deltaX = snapshot.positionX < 0.70 ? 0.18 : -0.18
        let deltaY = snapshot.positionY < 0.72 ? 0.07 : -0.07
        worker.applyExternalDisplacement(
            deltaX: deltaX,
            deltaY: deltaY,
            headingDelta: .pi / 4,
            revealToSelfModel: false
        )
        advance(force: true)
    }

    func triggerGoalConflict() {
        goalConflictRemaining = 5
        advance(force: true)
    }

    func introduceOtherAgent(contingent: Bool = true) {
        otherAgentRemaining = 6
        otherAgentIsContingent = contingent
        advance(force: true)
    }

    func revive() {
        worker.revive()
        advance(force: true)
    }

    var fullCNSManifest: FullCNSManifest? {
        worker.manifest
    }

    func inspectFullCNSNeurons(
        matching query: FullCNSNeuronQuery
    ) -> [FullCNSNeuronObservation] {
        worker.inspectNeurons(matching: query)
    }

    func inspectFullCNSNeuron(bodyID: UInt64) -> FullCNSNeuronObservation? {
        worker.inspectNeuron(bodyID: bodyID)
    }

    private func advance(force: Bool = false) {
        guard !advanceInFlight else { return }
        let now = Date()
        let delta = min(max(now.timeIntervalSince(lastStepAt), 0.001), 0.5)

        removeFoodIfExpired(at: now)
        guard !isPaused || force else { return }

        lastStepAt = now
        let stimulus = makeStimulus(deltaTime: delta, now: now)
        advanceInFlight = true
        worker.step(deltaTime: delta, stimulus: stimulus, now: now) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                self.advanceInFlight = false
                self.snapshot = snapshot
                self.consumeFoodIfNeeded(
                    deltaTime: delta,
                    contactStrength: stimulus.foodContact
                )
                self.touchPulse = max(0, self.touchPulse - delta * 2.4)
                self.contaminationPulse = max(0, self.contaminationPulse - delta * 0.8)
                self.sensorMaskRemaining = max(0, self.sensorMaskRemaining - delta)
                self.goalConflictRemaining = max(0, self.goalConflictRemaining - delta)
                self.otherAgentRemaining = max(0, self.otherAgentRemaining - delta)
                let wasReversed = self.reversedSteeringRemaining > 0
                self.reversedSteeringRemaining = max(0, self.reversedSteeringRemaining - delta)
                if wasReversed, self.reversedSteeringRemaining == 0 {
                    self.worker.setMotorControlTransform(forwardScale: 1, turnScale: 1)
                }

                if now.timeIntervalSince(self.lastSaveAt) >= 1 {
                    self.persistSnapshot(forceWidgetRefresh: false)
                }
            }
        }
    }

    private func makeStimulus(deltaTime: TimeInterval, now: Date) -> FlyStimulus {
        let currentMouse = NSEvent.mouseLocation
        let mouseDistance = hypot(
            currentMouse.x - previousMouseLocation.x,
            currentMouse.y - previousMouseLocation.y
        )
        previousMouseLocation = currentMouse
        let mouseSpeed = mouseDistance / max(deltaTime, 0.001)
        let novelty = min(max(mouseSpeed / 1_500, 0), 1)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let flyPoint = CGPoint(
            x: visibleFrame.minX + snapshot.positionX * visibleFrame.width,
            y: visibleFrame.minY + snapshot.positionY * visibleFrame.height
        )
        let cursorDistance = hypot(currentMouse.x - flyPoint.x, currentMouse.y - flyPoint.y)
        let threat = cursorDistance < 120 && mouseSpeed > 240
            ? min((120 - cursorDistance) / 120 + mouseSpeed / 1_800, 1)
            : 0
        let threatBearing = atan2(currentMouse.y - flyPoint.y, currentMouse.x - flyPoint.x)

        var foodOdor = 0.0
        var foodContact = 0.0
        var foodBearing: Double?
        var amberOdor = 0.0
        var berryOdor = 0.0
        if let food, food.isAvailable(at: now) {
            let dx = food.positionX - snapshot.positionX
            let dy = food.positionY - snapshot.positionY
            let distance = hypot(dx, dy)
            foodOdor = exp(-distance * 4.8) * food.odorStrength(at: now)
            foodContact = distance < 0.055 ? food.edibleStrength(at: now) : 0
            foodBearing = atan2(dy, dx)
            switch food.odorCue {
            case .amber: amberOdor = foodOdor
            case .berry: berryOdor = foodOdor
            }
        }

        let sensoryGain = sensorMaskRemaining > 0 ? 0.12 : 1.0
        let goalConflictActive = goalConflictRemaining > 0
        let otherPresent = otherAgentRemaining > 0
        let otherMotion = otherPresent
            ? 0.42 + abs(sin(now.timeIntervalSinceReferenceDate * 2.1)) * 0.48
            : 0
        return FlyStimulus(
            foodOdor: max(foodOdor, goalConflictActive ? 0.86 : 0) * sensoryGain,
            foodContact: foodContact * sensoryGain,
            foodBearingRadians: foodBearing,
            amberOdor: max(amberOdor, goalConflictActive ? 0.86 : 0) * sensoryGain,
            berryOdor: berryOdor * sensoryGain,
            threat: max(threat, goalConflictActive ? 0.62 : 0) * sensoryGain,
            threatBearingRadians: threatBearing,
            visualMotionBearingRadians: threatBearing,
            touch: touchPulse * sensoryGain,
            novelty: novelty * sensoryGain,
            contamination: max(contaminationPulse, goalConflictActive ? 0.58 : 0) * sensoryGain,
            sensorReliability: sensoryGain,
            otherAgentID: otherPresent ? "OTHER-ALPHA" : nil,
            otherAgentPresence: otherPresent ? sensoryGain : 0,
            otherAgentMotion: otherMotion * sensoryGain,
            otherAgentContingency: otherPresent
                ? (otherAgentIsContingent ? 0.88 : 0.14) : 0,
            otherAgentThreat: otherPresent && !otherAgentIsContingent ? 0.22 : 0.06
        )
    }

    private func consumeFoodIfNeeded(
        deltaTime: TimeInterval,
        contactStrength: Double
    ) {
        let feedingDrive = snapshot.feedingMotorDrive ?? 0
        guard feedingDrive > 0,
              contactStrength > 0,
              var updatedFood = food else { return }
        if updatedFood.consume(
            deltaTime: deltaTime,
            contactStrength: contactStrength * feedingDrive
        ) {
            food = nil
        } else {
            food = updatedFood
        }
    }

    private func removeFoodIfExpired(at now: Date) {
        guard let food, !food.isAvailable(at: now) else { return }
        self.food = nil
    }

    private func persistSnapshot(forceWidgetRefresh: Bool) {
        let shouldReloadWidget = widgetRefreshPolicy.shouldRefresh(
            for: snapshot,
            force: forceWidgetRefresh
        )
        lastSaveAt = Date()
        worker.persistAsync(
            force: forceWidgetRefresh,
            reloadWidget: shouldReloadWidget
        )
    }
}
