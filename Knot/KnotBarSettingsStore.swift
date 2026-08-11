import Combine
import Foundation

@MainActor
final class KnotBarSettingsStore: ObservableObject {
    static let shared = KnotBarSettingsStore()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isAutoHide: Bool
    @Published private(set) var autoHideDelay: Double
    @Published private(set) var revealOnHover: Bool
    @Published private(set) var separatorsHidden: Bool

    private enum Key {
        static let enabled = "knotBarEnabled"
        static let autoHide = "knotBarAutoHide"
        static let delay = "knotBarAutoHideDelay"
        static let hover = "knotBarRevealOnHover"
        static let separators = "knotBarSeparatorsHidden"
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        isAutoHide = UserDefaults.standard.object(forKey: Key.autoHide) as? Bool ?? true
        let savedDelay = UserDefaults.standard.double(forKey: Key.delay)
        autoHideDelay = savedDelay == 0 ? 10 : min(max(savedDelay, 3), 60)
        revealOnHover = UserDefaults.standard.object(forKey: Key.hover) as? Bool ?? false
        separatorsHidden = UserDefaults.standard.bool(forKey: Key.separators)
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        UserDefaults.standard.set(value, forKey: Key.enabled)
    }

    func setAutoHide(_ value: Bool) {
        isAutoHide = value
        UserDefaults.standard.set(value, forKey: Key.autoHide)
    }

    func setAutoHideDelay(_ value: Double) {
        autoHideDelay = min(max(value, 3), 60)
        UserDefaults.standard.set(autoHideDelay, forKey: Key.delay)
    }

    func setRevealOnHover(_ value: Bool) {
        revealOnHover = value
        UserDefaults.standard.set(value, forKey: Key.hover)
    }

    func setSeparatorsHidden(_ value: Bool) {
        separatorsHidden = value
        UserDefaults.standard.set(value, forKey: Key.separators)
    }
}
