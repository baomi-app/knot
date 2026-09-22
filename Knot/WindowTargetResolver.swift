import Foundation

enum WindowTargetAttribute {
    case focused
    case main
}

@MainActor
protocol WindowTargetAccess {
    associatedtype Window

    func window(for applicationPID: pid_t, attribute: WindowTargetAttribute) -> Window?
    func systemFocusedWindow() -> Window?
    func processIdentifier(of window: Window) -> pid_t?
    func frame(of window: Window) -> CGRect?
}

/// Keep the application captured before Knot activates. A failed AX lookup must
/// not make a later retry target Knot's own panel (or another application).
@MainActor
final class WindowTargetResolver<Access: WindowTargetAccess> {
    private let access: Access
    private var applicationPID: pid_t?
    private var cachedWindow: Access.Window?

    init(access: Access) {
        self.access = access
    }

    func capture(applicationPID: pid_t?, canReadWindows: Bool = true) {
        self.applicationPID = applicationPID
        cachedWindow = nil
        if canReadWindows {
            _ = resolve()
        }
    }

    func resolve() -> (window: Access.Window, frame: CGRect)? {
        guard let applicationPID, applicationPID > 0 else { return nil }

        if let cachedWindow, let target = target(for: cachedWindow, applicationPID: applicationPID) {
            return target
        }
        cachedWindow = nil

        // Query the known foreground application's AX object directly. The
        // system-wide focused-application attribute is not always available.
        if let window = access.window(for: applicationPID, attribute: .focused),
           let target = target(for: window, applicationPID: applicationPID) {
            cachedWindow = window
            return target
        }

        if let window = access.systemFocusedWindow(),
           let target = target(for: window, applicationPID: applicationPID) {
            cachedWindow = window
            return target
        }

        // Some apps stop exposing AXFocusedWindow as soon as a launcher opens,
        // but continue to expose AXMainWindow for the same application.
        if let window = access.window(for: applicationPID, attribute: .main),
           let target = target(for: window, applicationPID: applicationPID) {
            cachedWindow = window
            return target
        }
        return nil
    }

    private func target(
        for window: Access.Window,
        applicationPID: pid_t
    ) -> (window: Access.Window, frame: CGRect)? {
        guard access.processIdentifier(of: window) == applicationPID,
              let frame = access.frame(of: window),
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.size.width.isFinite, frame.size.height.isFinite,
              frame.size.width > 0, frame.size.height > 0 else { return nil }
        return (window, frame)
    }
}
