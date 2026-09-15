import Foundation

/// Coalesces updates and runs them after synchronous property setters finish.
@MainActor
final class KnotBarUpdateScheduler {
    private var pendingUpdate: DispatchWorkItem?

    func schedule(_ update: @escaping () -> Void) {
        guard pendingUpdate == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingUpdate = nil
            update()
        }
        pendingUpdate = work
        DispatchQueue.main.async(execute: work)
    }

    func cancel() {
        pendingUpdate?.cancel()
        pendingUpdate = nil
    }
}
