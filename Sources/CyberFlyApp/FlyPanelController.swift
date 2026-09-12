import AppKit
import Combine
import CyberFlyCore
import CyberFlySimulation
import SwiftUI

@MainActor
final class FlyPanelController {
    private let runtime: RuntimeController
    private let panel: NSPanel
    private let foodPanel: NSPanel
    private var snapshotSubscription: AnyCancellable?
    private var foodSubscription: AnyCancellable?
    private(set) var isVisible = true

    init(runtime: RuntimeController) {
        self.runtime = runtime
        let panelSize = CGSize(width: 37, height: 39)
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: DesktopFlyView(runtime: runtime))

        let foodPanelSize = CGSize(width: 42, height: 42)
        foodPanel = NSPanel(
            contentRect: CGRect(origin: .zero, size: foodPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        foodPanel.isOpaque = false
        foodPanel.backgroundColor = .clear
        foodPanel.hasShadow = false
        foodPanel.level = .floating
        foodPanel.hidesOnDeactivate = false
        foodPanel.ignoresMouseEvents = true
        foodPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        foodPanel.contentView = NSHostingView(rootView: FoodMarkerView(runtime: runtime))

        snapshotSubscription = runtime.$snapshot.sink { [weak self] snapshot in
            self?.move(to: snapshot)
        }
        foodSubscription = runtime.$food.sink { [weak self] food in
            self?.updateFood(food: food)
        }
    }

    func show() {
        isVisible = true
        panel.orderFrontRegardless()
        move(to: runtime.snapshot)
        updateFood(food: runtime.food)
    }

    func hide() {
        isVisible = false
        panel.orderOut(nil)
        foodPanel.orderOut(nil)
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    private func move(to snapshot: FlyStateSnapshot) {
        guard isVisible else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.minX + snapshot.positionX * max(frame.width - size.width, 1)
        let y = frame.minY + snapshot.positionY * max(frame.height - size.height, 1)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func updateFood(food: FoodResource?) {
        guard isVisible else {
            foodPanel.orderOut(nil)
            return
        }
        guard let food else {
            foodPanel.orderOut(nil)
            return
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = foodPanel.frame.size
        let x = frame.minX + food.positionX * max(frame.width - size.width, 1)
        let y = frame.minY + food.positionY * max(frame.height - size.height, 1)
        foodPanel.setFrameOrigin(CGPoint(x: x, y: y))
        foodPanel.orderFrontRegardless()
    }
}
