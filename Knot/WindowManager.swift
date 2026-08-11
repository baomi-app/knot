import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum WindowAction: String, Codable, CaseIterable, Hashable, Sendable {
    case leftHalf = "Left Half"
    case rightHalf = "Right Half"
    case topHalf = "Top Half"
    case bottomHalf = "Bottom Half"
    case maximize = "Maximize"
    case center = "Center"

    var subtitle: String {
        switch self {
        case .leftHalf: "Move the active window to the left 50%"
        case .rightHalf: "Move the active window to the right 50%"
        case .topHalf: "Move the active window to the top 50%"
        case .bottomHalf: "Move the active window to the bottom 50%"
        case .maximize: "Fill the current screen"
        case .center: "Center the active window without resizing"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.inset.filled"
        case .rightHalf: "rectangle.righthalf.inset.filled"
        case .topHalf: "rectangle.tophalf.inset.filled"
        case .bottomHalf: "rectangle.bottomhalf.inset.filled"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .center: "rectangle.center.inset.filled"
        }
    }
}

enum WindowManagerResult: Equatable, Sendable {
    case success(String)
    case permissionRequired
    case noFocusedWindow
    case unsupported

    var message: String {
        switch self {
        case .success(let action): "\(action) applied"
        case .permissionRequired: "Allow Accessibility access, then reopen Knot"
        case .noFocusedWindow: "No active window was found"
        case .unsupported: "This app does not allow its window to be resized"
        }
    }
}

enum WindowGeometry {
    static func frame(
        for action: WindowAction,
        current: CGRect,
        visible: CGRect
    ) -> CGRect {
        let halfWidth = floor(visible.width / 2)
        let halfHeight = floor(visible.height / 2)

        switch action {
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: visible.height)
        case .rightHalf:
            return CGRect(
                x: visible.minX + halfWidth,
                y: visible.minY,
                width: visible.width - halfWidth,
                height: visible.height
            )
        case .topHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(
                x: visible.minX,
                y: visible.minY + halfHeight,
                width: visible.width,
                height: visible.height - halfHeight
            )
        case .maximize:
            return visible
        case .center:
            let width = min(current.width, visible.width)
            let height = min(current.height, visible.height)
            return CGRect(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2,
                width: width,
                height: height
            ).integral
        }
    }
}

@MainActor
enum WindowManager {
    private static var targetWindow: AXUIElement?

    static func captureTarget() {
        guard isTrusted(prompt: false) else {
            targetWindow = nil
            return
        }
        targetWindow = focusedWindow()
    }

    static func perform(_ action: WindowAction) -> WindowManagerResult {
        guard isTrusted(prompt: true) else { return .permissionRequired }
        guard let window = targetWindow,
              let currentFrame = frame(of: window) else {
            return .noFocusedWindow
        }
        guard let visibleFrame = visibleFrame(containing: currentFrame) else {
            return .unsupported
        }

        let target = WindowGeometry.frame(for: action, current: currentFrame, visible: visibleFrame)
        guard set(frame: target, for: window) else { return .unsupported }
        return .success(action.rawValue)
    }

    static func performCurrent(_ action: WindowAction) -> WindowManagerResult {
        captureTarget()
        return perform(action)
    }

    static func isTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        return AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }

    private static func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var applicationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &applicationValue
        ) == .success,
              let applicationValue,
              CFGetTypeID(applicationValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let application = unsafeDowncast(applicationValue, to: AXUIElement.self)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
              let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(windowValue, to: AXUIElement.self)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
              AXUIElementCopyAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                &sizeValue
              ) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private static func set(frame: CGRect, for window: AXUIElement) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let positionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeResult = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        return positionResult == .success && sizeResult == .success
    }

    private static func visibleFrame(containing windowFrame: CGRect) -> CGRect? {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        let screen = NSScreen.screens.first { screen in
            guard let displayBounds = displayBounds(for: screen) else { return false }
            return displayBounds.contains(center)
        } ?? NSScreen.main

        guard let screen,
              let displayBounds = displayBounds(for: screen) else { return nil }

        let topInset = screen.frame.maxY - screen.visibleFrame.maxY
        let leftInset = screen.visibleFrame.minX - screen.frame.minX
        return CGRect(
            x: displayBounds.minX + leftInset,
            y: displayBounds.minY + topInset,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )
    }

    private static func displayBounds(for screen: NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }
}
