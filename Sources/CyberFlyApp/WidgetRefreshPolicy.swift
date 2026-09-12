import CyberFlyCore
import Foundation

struct WidgetRefreshPolicy {
    private var lastFingerprint = ""
    private var lastRefreshAt = Date.distantPast
    let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 15) {
        self.minimumInterval = minimumInterval
    }

    mutating func shouldRefresh(
        for snapshot: FlyStateSnapshot,
        now: Date = Date(),
        force: Bool = false
    ) -> Bool {
        let fingerprintChanged = snapshot.displayFingerprint != lastFingerprint
        let intervalElapsed = now.timeIntervalSince(lastRefreshAt) >= minimumInterval
        guard force || fingerprintChanged && intervalElapsed else { return false }
        lastFingerprint = snapshot.displayFingerprint
        lastRefreshAt = now
        return true
    }
}

