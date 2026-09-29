import ApplicationServices
import Foundation

/// AppKit state is captured on the main actor. No UI objects cross into the
/// reader, and all synchronous accessibility IPC runs on this separate actor.
struct KnotBarMenuBarReadRequest: Sendable {
    let agentPID: pid_t
    let bundleIdentifiersByPID: [pid_t: String]
    let ownBundleIdentifier: String
    let boundaryX: CGFloat
}

actor KnotBarMenuBarReader {
    func read(_ request: KnotBarMenuBarReadRequest) -> KnotBarVisibilityPolicy? {
        var scan = Scan(request: request)
        return scan.read()
    }

    private struct Scan {
        let request: KnotBarMenuBarReadRequest
        private let deadline = ProcessInfo.processInfo.systemUptime + 1
        private var failed = false

        init(request: KnotBarMenuBarReadRequest) {
            self.request = request
        }

        mutating func read() -> KnotBarVisibilityPolicy? {
            let agent = AXUIElementCreateApplication(request.agentPID)
            let windows = children(of: agent).filter { role(of: $0) == "AXWindow" }
            var bestGroups: [(String, CGRect)]?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            var boundaryX = request.boundaryX

            for window in windows {
                // Resolve each group's PID and frame only once per scan.
                let groups = children(of: window).compactMap { element -> (String, CGRect)? in
                    guard let bundleID = bundleIdentifier(in: element), let frame = frame(of: element) else {
                        return nil
                    }
                    return (bundleID, frame)
                }
                for (bundleID, frame) in groups where bundleID == request.ownBundleIdentifier {
                    let distance = abs(frame.minX - request.boundaryX)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestGroups = groups
                        // Use the boundary in the same AX snapshot, since the
                        // button may have moved while this read was queued.
                        boundaryX = frame.minX
                    }
                }
            }
            guard !failed, bestDistance < 80, let groups = bestGroups else { return nil }

            var left = Set<String>()
            var right = Set<String>()
            for (bundleID, frame) in groups {
                if frame.minX < boundaryX - 1 { left.insert(bundleID) }
                else if frame.minX > boundaryX + 1 { right.insert(bundleID) }
            }
            return KnotBarVisibilityPolicy(
                runningBundleIdentifiers: Set(request.bundleIdentifiersByPID.values),
                hidden: left.subtracting(right),
                ownBundleIdentifier: request.ownBundleIdentifier
            )
        }

        private mutating func bundleIdentifier(in element: AXUIElement, depth: Int = 0) -> String? {
            guard !failed, depth <= 3 else { return nil }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            if pid != request.agentPID, let bundleID = request.bundleIdentifiersByPID[pid] {
                return bundleID
            }
            for child in children(of: element) {
                if let bundleID = bundleIdentifier(in: child, depth: depth + 1) { return bundleID }
            }
            return nil
        }

        private mutating func attribute(_ name: CFString, of element: AXUIElement) -> CFTypeRef? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard !failed, remaining > 0 else {
                failed = true
                return nil
            }
            // AX timeouts apply only to the exact element, not its children.
            AXUIElementSetMessagingTimeout(element, Float(min(0.15, remaining)))
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name, &value)
            if error == .cannotComplete { failed = true }
            return error == .success ? value : nil
        }

        private mutating func children(of element: AXUIElement) -> [AXUIElement] {
            attribute(kAXChildrenAttribute as CFString, of: element) as? [AXUIElement] ?? []
        }

        private mutating func role(of element: AXUIElement) -> String {
            attribute(kAXRoleAttribute as CFString, of: element) as? String ?? ""
        }

        private mutating func frame(of element: AXUIElement) -> CGRect? {
            guard let value = attribute("AXFrame" as CFString, of: element),
                  CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var frame = CGRect.zero
            guard AXValueGetValue(value as! AXValue, .cgRect, &frame) else { return nil }
            return frame
        }
    }
}
