import AppKit
import SwiftUI

@main
struct CyberFlyApplication: App {
    @NSApplicationDelegateAdaptor(CyberFlyAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class CyberFlyAppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: RuntimeController?
    private var flyPanelController: FlyPanelController?
    private var statusMenuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        let runtime = RuntimeController()
        let flyPanelController = FlyPanelController(runtime: runtime)
        let statusMenuController = StatusMenuController(runtime: runtime, flyPanelController: flyPanelController)

        self.runtime = runtime
        self.flyPanelController = flyPanelController
        self.statusMenuController = statusMenuController

        flyPanelController.show()
        runtime.start()
        statusMenuController.showNeuralLab()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stopAndSave()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "cyberfly" }) else { return }
        if url.host == "lab" || url.path == "/lab" {
            statusMenuController?.showNeuralLab()
        } else {
            statusMenuController?.showDashboard()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        statusMenuController?.showNeuralLab()
        return true
    }
}
