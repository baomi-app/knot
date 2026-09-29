import Foundation

/// Coalesces layout changes, retries briefly after launches, and checks for
/// late status items at a low frequency. Only one read can be in flight.
@MainActor
final class KnotBarMenuBarMonitor {
    struct Timing {
        var debounce: TimeInterval = 0.2
        var retries: [TimeInterval] = [0.5, 1.5, 3, 5, 10]
        var fallback: TimeInterval = 30
    }

    private(set) var isRunning = false
    private let timing: Timing
    private let read: @MainActor () async -> KnotBarVisibilityPolicy?
    private let onRead: @MainActor (KnotBarVisibilityPolicy?) -> Void
    private var scheduledRead: Task<Void, Never>?
    private var retries: Task<Void, Never>?
    private var fallbackTimer: Timer?
    private var isReading = false
    private var needsRead = false
    private var revision: UInt64 = 0

    init(
        timing: Timing = Timing(),
        read: @escaping @MainActor () async -> KnotBarVisibilityPolicy?,
        onRead: @escaping @MainActor (KnotBarVisibilityPolicy?) -> Void
    ) {
        self.timing = timing
        self.read = read
        self.onRead = onRead
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let timer = Timer(timeInterval: timing.fallback, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.enqueueRead() }
        }
        timer.tolerance = timing.fallback / 6
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        layoutMayHaveChanged()
    }

    func layoutMayHaveChanged() {
        guard isRunning else { return }
        revision &+= 1
        enqueueRead()
        retries?.cancel()
        let delays = timing.retries
        retries = Task { [weak self] in
            var previous: TimeInterval = 0
            for delay in delays {
                do {
                    try await Task.sleep(for: .seconds(delay - previous))
                } catch { return }
                guard let self, self.isRunning, !Task.isCancelled else { return }
                self.enqueueRead()
                previous = delay
            }
        }
    }

    func stop() {
        isRunning = false
        revision &+= 1
        needsRead = false
        scheduledRead?.cancel()
        scheduledRead = nil
        retries?.cancel()
        retries = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        // AX IPC cannot be cancelled mid-call. Leave isReading set until the
        // bounded read finishes, then discard its result using the revision.
    }

    private func enqueueRead() {
        guard isRunning else { return }
        needsRead = true
        guard !isReading, scheduledRead == nil else { return }
        let delay = timing.debounce
        scheduledRead = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch { return }
            guard let self, self.isRunning, !Task.isCancelled else { return }
            self.scheduledRead = nil
            await self.performRead()
        }
    }

    private func performRead() async {
        needsRead = false
        isReading = true
        let readRevision = revision
        let snapshot = await read()
        isReading = false
        if isRunning, revision == readRevision {
            onRead(snapshot)
        }
        if needsRead { enqueueRead() }
    }
}
