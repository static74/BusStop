import Foundation
import Observation

/// Runs a closure now and again after every change to any `@Observable`
/// property it read, on the main actor.
///
/// `withObservationTracking` fires only once per registration, so the loop
/// re-arms itself after each change. The change callback arrives in the
/// mutation's `willSet`; the closure runs on the next main-actor turn, after
/// the new value is in place. Call `cancel()` or release the loop to stop it.
final class ObservationLoop {
    private let body: () -> Void
    private var isCancelled = false

    init(_ body: @escaping () -> Void) {
        self.body = body
        run()
    }

    func cancel() {
        isCancelled = true
    }

    private func run() {
        guard !isCancelled else { return }
        withObservationTracking {
            body()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.run()
            }
        }
    }
}
