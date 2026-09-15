import Foundation

struct KnotBarVisibilityPolicy: Equatable {
    let allowed: Set<String>
    let hidden: Set<String>
    private let ownBundleIdentifier: String

    init(runningBundleIdentifiers: Set<String>, hidden: Set<String>, ownBundleIdentifier: String) {
        self.ownBundleIdentifier = ownBundleIdentifier
        self.hidden = Set(hidden.filter {
            $0 != ownBundleIdentifier && !$0.hasPrefix("com.apple.")
        })
        allowed = runningBundleIdentifiers.subtracting(self.hidden)
            .union([ownBundleIdentifier, "com.apple.systemuiserver"])
    }

    func updatingRunningApplications(_ bundleIdentifiers: Set<String>) -> Self {
        Self(
            runningBundleIdentifiers: bundleIdentifiers,
            hidden: hidden,
            ownBundleIdentifier: ownBundleIdentifier
        )
    }
}
