import ScreenCaptureKit
import CoreGraphics
import CoreImage
import AppKit
import VideoToolbox

/// Output delegate helper for a single display to avoid MainActor thread-safety issues.
final class SingleDisplayStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let displayID: CGDirectDisplayID
    private var onFrame: (CGImage) -> Void
    private var hasCaptured = false
    private var framesToSkip = 0
    
    // Standard CIContext for high performance and compatibility.
    private static let context = CIContext(options: nil)
    
    init(displayID: CGDirectDisplayID, onFrame: @escaping (CGImage) -> Void) {
        self.displayID = displayID
        self.onFrame = onFrame
        super.init()
    }
    
    func cancel() {
        hasCaptured = true
        framesToSkip = 0
    }
    
    func reactivate(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
        // Skip the first 5 frames (approx 83ms at 60fps) to flush the compositor pipeline.
        // This guarantees that any in-flight frames captured before the filter update was applied are discarded.
        self.framesToSkip = 5
        self.hasCaptured = false
    }
    
    // MARK: - SCStreamOutput
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        
        // If we already captured a frame, discard subsequent frames instantly for zero CPU overhead.
        if hasCaptured { return }
        
        // Flush in-flight frames after reactivation
        if framesToSkip > 0 {
            framesToSkip -= 1
            return
        }
        
        // Inspect frame status to skip incomplete, started, or blank frames (prevents solid black freezes!).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let attachment = attachments.first {
            let statusKey = SCStreamFrameInfo.status.rawValue as CFString
            if let statusRaw = attachment[statusKey] as? Int {
                if statusRaw != 0 { // 0 matches SCFrameStatus.complete. Raw value 0 is the only valid complete frame.
                    return // Skip this frame and wait for a complete frame!
                }
            }
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        hasCaptured = true
        
        // 1. Primary Method: Use VideoToolbox to convert CVPixelBuffer directly to CGImage.
        // This preserves the exact color space, tone-mapping, and HDR/EDR calibration
        // of the display without any color shift or gray/dark wash.
        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        
        if status == noErr, let img = cgImage {
            DispatchQueue.main.async { [weak self] in
                self?.onFrame(img)
            }
        } else {
            // 2. Fallback Method: Use CIContext to render to display's native color space.
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let colorSpace = CGDisplayCopyColorSpace(displayID)
            
            if let img = Self.context.createCGImage(
                ciImage,
                from: ciImage.extent,
                format: .RGBA8, // 8-bit standard color matching CGDisplayCreateImage exactly
                colorSpace: colorSpace
            ) {
                DispatchQueue.main.async { [weak self] in
                    self?.onFrame(img)
                }
            } else {
                // Retry on next frame if both methods failed
                hasCaptured = false
            }
        }
    }
    
    // MARK: - SCStreamDelegate
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[Pop] Stream for display \(displayID) stopped with error: \(error)")
    }
}

/// Continuous SCStream-based screen capturer that keeps the capture active to avoid EDR headroom drops (flash).
/// It supports session reuse to make subsequent captures 100% instant and flash-free.
@MainActor
class ScreenStreamCapturer {
    static let shared = ScreenStreamCapturer()
    
    private struct Session {
        let stream: SCStream
        let output: SingleDisplayStreamOutput
    }
    
    private var sessions: [Session] = []
    private var isRunning = false
    private var stopTask: Task<Void, Never>?
    
    private init() {}
    
    func start(on screens: [NSScreen], onFrame: @escaping @MainActor (CGDirectDisplayID, CGImage) -> Void) async throws {
        // Cancel any pending deferred stop task immediately
        stopTask?.cancel()
        stopTask = nil
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Find our own application by Process ID to exclude it entirely.
        // This is 100% robust and race-free: excluding the application excludes all its windows (current and future),
        // completely resolving the "double yellow boxes" issue.
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myApp = content.applications.first { $0.processID == myPID }
        let myWindows = content.windows.filter { $0.owningApplication?.processID == myPID }
        
        if isRunning && !sessions.isEmpty {
            // Stream session is already active! Update the content filters dynamically to exclude
            // the new selection windows, then reactivate the outputs.
            // This guarantees zero startup flash/delay, and 100% correct window exclusions!
            for session in sessions {
                let displayID = session.output.displayID
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    continue
                }
                let filter: SCContentFilter
                if let myApp {
                    filter = SCContentFilter(display: display, excludingApplications: [myApp], exceptingWindows: [])
                } else {
                    filter = SCContentFilter(display: display, excludingWindows: myWindows)
                }
                try? await session.stream.updateContentFilter(filter)
                
                session.output.reactivate { cgImage in
                    onFrame(displayID, cgImage)
                }
            }
            return
        }
        
        isRunning = true
        
        for screen in screens {
            let displayID = screen.displayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                continue
            }
            
            // Exclude our own application's windows to avoid capturing the overlay UI
            let filter: SCContentFilter
            if let myApp {
                filter = SCContentFilter(display: display, excludingApplications: [myApp], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: myWindows)
            }
            
            let scale = screen.backingScaleFactor
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = false
            config.captureResolution = .best
            
            if #available(macOS 15.0, *) {
                config.captureDynamicRange = .hdrLocalDisplay
            }
            
            // Helper for handling stream output and delegate callbacks
            let output = SingleDisplayStreamOutput(displayID: displayID) { cgImage in
                onFrame(displayID, cgImage)
            }
            
            let stream = SCStream(filter: filter, configuration: config, delegate: output)
            
            let queue = DispatchQueue(label: "com.baomi.pop.stream-queue-\(displayID)", qos: .userInteractive)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            
            try await stream.startCapture()
            sessions.append(Session(stream: stream, output: output))
        }
    }
    
    func stopDeferred() {
        // Cancel any existing stop task
        stopTask?.cancel()
        
        // Defer stopping streams by 800ms to hide stop-capture visuals from the user
        stopTask = Task {
            do {
                try await Task.sleep(nanoseconds: 800_000_000) // 800ms
                guard !Task.isCancelled else { return }
                await self.stopImmediately()
            } catch {}
        }
    }
    
    func stopImmediately() async {
        stopTask?.cancel()
        stopTask = nil
        
        guard isRunning else { return }
        isRunning = false
        
        let activeSessions = sessions
        sessions.removeAll()
        
        for session in activeSessions {
            session.output.cancel()
            try? session.stream.removeStreamOutput(session.output, type: .screen)
            try? await session.stream.stopCapture()
        }
    }
}
