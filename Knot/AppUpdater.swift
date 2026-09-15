import AppKit
import Combine
import Sparkle

/// The update-signing private key is used only by the release tools. The app
/// verifies updates using the public key embedded in its signed Info.plist.
@MainActor
final class AppUpdater: NSObject, ObservableObject, NSMenuItemValidation {
    static let shared = AppUpdater()

    @Published private var sparkleCanCheckForUpdates = false
    @Published private(set) var isCheckingFeed = false
    @Published private(set) var lastCheckMessage: String?
    @Published private(set) var automaticChecksEnabled = false
    @Published private(set) var automaticDownloadsEnabled = false
    @Published private(set) var configurationError: String?

    private var controller: SPUStandardUpdaterController?

    var canCheckForUpdates: Bool { sparkleCanCheckForUpdates && !isCheckingFeed }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    var isAvailable: Bool { controller != nil && configurationError == nil }

    func start() {
        guard controller == nil else { return }
        if let error = UpdateConfiguration.issue(in: Bundle.main.infoDictionary ?? [:]) {
            configurationError = error
            return
        }

        let candidate = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        do {
            // Use the throwing API so a misconfigured development build does
            // not show an unsolicited Sparkle error window on every launch.
            try candidate.updater.start()
            controller = candidate
            configurationError = nil
            candidate.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$sparkleCanCheckForUpdates)
            candidate.updater.publisher(for: \.automaticallyChecksForUpdates)
                .assign(to: &$automaticChecksEnabled)
            candidate.updater.publisher(for: \.automaticallyDownloadsUpdates)
                .assign(to: &$automaticDownloadsEnabled)
        } catch {
            configurationError = "Updates are unavailable in this build: \(error.localizedDescription)"
        }
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        start()
        guard canCheckForUpdates, let controller,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feed) else { return }
        NSApp.activate(ignoringOtherApps: true)
        isCheckingFeed = true
        lastCheckMessage = nil
        Task { [weak self] in
            let issue = await UpdateFeedAvailability.issue(at: feedURL)
            guard let self else { return }
            self.isCheckingFeed = false
            if let issue {
                self.lastCheckMessage = issue
                let alert = NSAlert()
                alert.messageText = "Updates Unavailable"
                alert.informativeText = issue
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
            // Availability is not authenticity: only Sparkle's signed update
            // flow decides whether an update is valid and may be installed.
            controller.checkForUpdates(sender)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return canCheckForUpdates
        }
        return true
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloadsEnabled(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }
}
