import AppKit
import Combine
import CyberFlyCore
import CyberFlySimulation
import Foundation
import WidgetKit

@MainActor
final class RuntimeController: ObservableObject {
    @Published private(set) var snapshot: FlyStateSnapshot
    @Published private(set) var isPaused = false
    @Published private(set) var food: FoodResource?

    private let simulation: FlySimulation
    private let snapshotStore: FlySnapshotStore
    private let learningMemoryStore: MaleCNSLearningMemoryStore
    private var lastSavedLearningRevision: UInt64
    private var timer: Timer?
    private var lastStepAt = Date()
    private var lastSaveAt = Date.distantPast
    private var widgetRefreshPolicy = WidgetRefreshPolicy()
    private var previousMouseLocation = NSEvent.mouseLocation
    private var touchPulse = 0.0
    private var contaminationPulse = 0.0

    init(
        simulation: FlySimulation? = nil,
        snapshotStore: FlySnapshotStore = FlySnapshotStore(),
        learningMemoryStore: MaleCNSLearningMemoryStore? = nil
    ) {
        self.snapshotStore = snapshotStore
        let resolvedMemoryStore = learningMemoryStore
            ?? MaleCNSLearningMemoryStore.nextToSnapshot(snapshotStore.snapshotURL)
        self.learningMemoryStore = resolvedMemoryStore
        let resolvedSimulation: FlySimulation
        if let simulation {
            resolvedSimulation = simulation
        } else if let savedSnapshot = snapshotStore.load() {
            resolvedSimulation = FlySimulation(
                restoring: savedSnapshot,
                learningMemory: resolvedMemoryStore.load()
            )
        } else {
            resolvedSimulation = FlySimulation(learningMemory: resolvedMemoryStore.load())
        }
        self.simulation = resolvedSimulation
        self.lastSavedLearningRevision = resolvedSimulation.learningMemoryRevision
        self.snapshot = resolvedSimulation.step(deltaTime: 0.001)
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
        persistSnapshot(forceWidgetRefresh: true)
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
        simulation.addContamination(0.42)
    }

    func revive() {
        simulation.revive()
        advance(force: true)
    }

    private func advance(force: Bool = false) {
        let now = Date()
        let delta = min(max(now.timeIntervalSince(lastStepAt), 0.001), 0.5)
        lastStepAt = now

        removeFoodIfExpired(at: now)
        guard !isPaused || force else { return }

        let stimulus = makeStimulus(deltaTime: delta, now: now)
        snapshot = simulation.step(deltaTime: delta, stimulus: stimulus, now: now)
        consumeFoodIfNeeded(deltaTime: delta, contactStrength: stimulus.foodContact)

        touchPulse = max(0, touchPulse - delta * 2.4)
        contaminationPulse = max(0, contaminationPulse - delta * 0.8)

        if now.timeIntervalSince(lastSaveAt) >= 1 {
            persistSnapshot(forceWidgetRefresh: false)
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

        return FlyStimulus(
            foodOdor: foodOdor,
            foodContact: foodContact,
            foodBearingRadians: foodBearing,
            amberOdor: amberOdor,
            berryOdor: berryOdor,
            threat: threat,
            threatBearingRadians: threatBearing,
            visualMotionBearingRadians: threatBearing,
            touch: touchPulse,
            novelty: novelty,
            contamination: contaminationPulse
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
        do {
            try snapshotStore.save(snapshot)
            if forceWidgetRefresh || simulation.learningMemoryRevision != lastSavedLearningRevision {
                try learningMemoryStore.save(simulation.exportLearningMemory())
                lastSavedLearningRevision = simulation.learningMemoryRevision
            }
            lastSaveAt = Date()
        } catch {
            NSLog("CyberFly snapshot save failed: %@", error.localizedDescription)
            return
        }

        if widgetRefreshPolicy.shouldRefresh(for: snapshot, force: forceWidgetRefresh) {
            WidgetCenter.shared.reloadTimelines(ofKind: FlyWidgetKind.value)
        }
    }
}
