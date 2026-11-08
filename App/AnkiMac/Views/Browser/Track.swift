import Foundation
import Observation

/// Runs `apply` now, and again whenever an Observable property it read
/// changes: the AppKit views' equivalent of a SwiftUI body. The re-run waits
/// for the main queue, because observers are told before the change lands.
/// Stops once `apply` reads nothing, as when its owner is gone.
func track(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { track(apply) }
        }
    }
}
