import Combine
import Foundation

/// Keeps application scans serial, including scanners that do not support cancellation.
@MainActor
final class ApplicationIndex: ObservableObject {
    @Published private(set) var applications: [ScannedApplication] = []
    @Published private(set) var isLoading = true

    private let scan: @Sendable () async -> [ScannedApplication]
    private var scanTask: Task<Void, Never>?
    private var scanIdentifier: UUID?
    private var generation: UInt64 = 0
    private var isStarted = false
    private var hasPendingRefresh = false

    init(scan: @escaping @Sendable () async -> [ScannedApplication] = { await AppScanner.scan() }) {
        self.scan = scan
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        generation &+= 1
        isLoading = applications.isEmpty
        refresh()
    }

    func refresh() {
        guard isStarted else { return }
        hasPendingRefresh = true
        beginNextScanIfNeeded()
    }

    func stop() {
        isStarted = false
        generation &+= 1
        hasPendingRefresh = false
        isLoading = false
        // Keep the handle until completion: Task.cancel() does not guarantee that
        // filesystem enumeration, or an injected scanner, stops immediately.
        scanTask?.cancel()
    }

    private func beginNextScanIfNeeded() {
        guard isStarted, hasPendingRefresh, scanTask == nil else { return }
        hasPendingRefresh = false
        let scanGeneration = generation
        let identifier = UUID()
        scanIdentifier = identifier
        let scan = scan
        scanTask = Task { [weak self] in
            let applications = await scan()
            self?.scanCompleted(
                applications,
                generation: scanGeneration,
                identifier: identifier,
                wasCancelled: Task.isCancelled
            )
        }
    }

    private func scanCompleted(
        _ applications: [ScannedApplication],
        generation scanGeneration: UInt64,
        identifier: UUID,
        wasCancelled: Bool
    ) {
        guard scanIdentifier == identifier else { return }
        scanTask = nil
        scanIdentifier = nil

        if isStarted, generation == scanGeneration, !wasCancelled {
            if self.applications != applications {
                self.applications = applications
            }
            isLoading = false
        }
        beginNextScanIfNeeded()
    }
}
