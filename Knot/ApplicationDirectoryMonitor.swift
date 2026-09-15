import CoreServices
import Foundation

/// Recursively watches only application search roots, without polling the disk.
@MainActor
final class ApplicationDirectoryMonitor {
    private let roots: [URL]
    private let debounceInterval: TimeInterval
    private let onChange: @MainActor () -> Void
    private let streamStorage = ApplicationEventStreamStorage()
    private var pendingChange: DispatchWorkItem?

    init(
        roots: [URL] = AppScanner.defaultRoots,
        debounceInterval: TimeInterval = 0.75,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.roots = roots.map(Self.canonicalURL)
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    func start() {
        guard streamStorage.stream == nil, !roots.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagWatchRoot |
            kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            { _, context, count, eventPaths, eventFlags, _ in
                guard let context else { return }
                let monitor = Unmanaged<ApplicationDirectoryMonitor>.fromOpaque(context).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                // Delivery is explicitly configured on the main dispatch queue.
                MainActor.assumeIsolated {
                    for index in 0..<min(count, paths.count) {
                        if ApplicationDirectoryMonitor.shouldRefresh(path: paths[index], flags: eventFlags[index], roots: monitor.roots) {
                            monitor.scheduleChange()
                            break
                        }
                    }
                }
            },
            &context,
            Self.watchPaths(for: roots) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else { return }
        streamStorage.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        if !FSEventStreamStart(stream) {
            streamStorage.stop()
        }
    }

    func stop() {
        pendingChange?.cancel()
        pendingChange = nil
        streamStorage.stop()
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            guard let self, self.streamStorage.stream != nil else { return }
            self.pendingChange = nil
            self.onChange()
        }
        pendingChange = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: pending)
    }

    private static func watchPaths(for roots: [URL]) -> [String] {
        var paths = Set<String>()
        for root in roots {
            var existing = root
            while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
                existing.deleteLastPathComponent()
            }
            // ~/Applications may not exist yet. Its nearest existing parent
            // lets us notice its creation; shouldRefresh still filters events
            // to the intended application roots.
            paths.insert(existing.path)
        }
        return paths.sorted()
    }

    nonisolated static func shouldRefresh(
        path: String,
        flags: FSEventStreamEventFlags,
        roots: [URL]
    ) -> Bool {
        let mustRescan = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs |
            kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped |
            kFSEventStreamEventFlagRootChanged |
            kFSEventStreamEventFlagMount |
            kFSEventStreamEventFlagUnmount
        )
        if flags & mustRescan != 0 { return true }

        let url = canonicalURL(URL(fileURLWithPath: path))
        guard let root = roots.first(where: {
            url.path == $0.path || url.path.hasPrefix($0.path + "/")
        }) else { return false }
        let components = Array(url.pathComponents.dropFirst(root.pathComponents.count))
        let appComponent = components.firstIndex { $0.lowercased().hasSuffix(".app") }

        if let appComponent {
            // Bundle installation/removal, plus metadata arriving after a bundle
            // directory was created, can change search results. Ordinary writes
            // to app resources and caches cannot.
            if appComponent == components.count - 1 { return true }
            return ["Info.plist", "InfoPlist.strings"].contains(url.lastPathComponent)
        }

        let structureChanged = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated |
            kFSEventStreamEventFlagItemRemoved |
            kFSEventStreamEventFlagItemRenamed
        )
        // A newly moved folder can contain apps several levels below the root.
        return flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
            && flags & structureChanged != 0
    }

    private nonisolated static func canonicalURL(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var missingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            missingComponents.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        // Resolving a removed path directly may preserve /private/var even
        // though the corresponding existing root resolves to /var. Resolve
        // the surviving ancestor, then rebuild the no-longer-existing suffix.
        return missingComponents.reversed().reduce(existing.resolvingSymlinksInPath()) {
            $0.appendingPathComponent($1)
        }
    }
}

/// Owns the C stream so abandoning a monitor also releases its callbacks.
private final class ApplicationEventStreamStorage {
    var stream: FSEventStreamRef?

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
