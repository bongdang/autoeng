public enum WindowObservationStatus: Equatable, Sendable {
    case available
    case permissionRequired
    case unsupported
    case failed(Int32)
}

@MainActor
public protocol WindowObservationBackend: AnyObject {
    associatedtype Window: Equatable
    var isTrusted: Bool { get }
    func beginObserving(processID: Int32) -> WindowObservationStatus
    func endObserving(processID: Int32)
    func focusedWindow(processID: Int32) -> Window?
    func selectedTab(processID: Int32, window: Window) -> Window?
    var windowReadStatus: WindowObservationStatus { get }
    var requiresWindowReconciliation: Bool { get }
    func existingWindows(processID: Int32) -> [Window]?
}

public extension WindowObservationBackend {
    func selectedTab(processID: Int32, window: Window) -> Window? { nil }
    var windowReadStatus: WindowObservationStatus { .available }
    var requiresWindowReconciliation: Bool { false }
    func existingWindows(processID: Int32) -> [Window]? { nil }
}

@MainActor
public final class WindowFocusResolver<Backend: WindowObservationBackend> {
    private let backend: Backend
    private var observedPID: Int32?
    private var windows: [Int32: [(Backend.Window, Int)]] = [:]
    private var nextToken = 1
    private var selected: (window: Backend.Window, tab: Backend.Window, token: Int)?
    private var nextTabToken = 1
    public private(set) var status: WindowObservationStatus = .permissionRequired
    public init(backend: Backend) { self.backend = backend }
    public func acceptsWindowEvent(processID: Int32, foreground: FocusContext?) -> Bool {
        backend.isTrusted && observedPID == processID && foreground?.processID == processID
    }
    public func resolve(_ context: FocusContext?, targets: Set<String>) -> FocusContext? {
        // Leaving a process releases its windows even when AX permission is unavailable.
        // Reconnecting to the same process after permission recovery keeps live identities.
        if let context, targets.contains(context.bundleID) {
            if windows.keys.contains(where: { $0 != context.processID }) {
                windows = windows.filter { $0.key == context.processID }
            }
        } else { windows.removeAll() }
        guard backend.isTrusted else {
            detach()
            status = .permissionRequired
            return context
        }
        guard let context, targets.contains(context.bundleID) else {
            detach(clearWindows: true)
            status = .available
            return context
        }
        let attachedNow = observedPID != context.processID
        if attachedNow {
            detach()
            status = backend.beginObserving(processID: context.processID)
            guard status == .available else { return context }
            observedPID = context.processID
        }
        let focused = backend.focusedWindow(processID: context.processID)
        status = backend.windowReadStatus
        guard status == .available else { selected = nil; return context }
        if attachedNow || backend.requiresWindowReconciliation {
            pruneClosedWindows(processID: context.processID, preserving: focused)
            status = backend.windowReadStatus
            guard status == .available else { selected = nil; return context }
        }
        guard let window = focused else { selected = nil; return context }
        let token: Int
        if let existing = windows[context.processID]?.first(where: { $0.0 == window }) {
            token = existing.1
        } else {
            token = nextToken
            nextToken += 1
            windows[context.processID, default: []].append((window, token))
        }
        let tabID: Int?
        if let tab = backend.selectedTab(processID: context.processID, window: window) {
            if selected?.window != window || selected?.tab != tab {
                selected = (window, tab, nextTabToken)
                nextTabToken += 1
            }
            tabID = selected?.token
        } else { selected = nil; tabID = nil }
        return FocusContext(bundleID: context.bundleID, processID: context.processID, windowID: token, tabID: tabID)
    }

    public func processTerminated(_ pid: Int32) {
        if observedPID == pid { detach() }
        windows.removeValue(forKey: pid)
    }

    public func windowDestroyed(_ window: Backend.Window, processID: Int32) {
        guard observedPID == processID else { return }
        if selected?.window == window { selected = nil }
        windows[processID]?.removeAll { $0.0 == window }
    }
    public func pruneClosedWindows(processID: Int32, preserving focused: Backend.Window? = nil) {
        guard observedPID == processID, let live = backend.existingWindows(processID: processID) else { return }
        windows[processID]?.removeAll { candidate in candidate.0 != focused && !live.contains(candidate.0) }
    }

    public func stop() {
        detach()
        windows.removeAll()
    }

    private func detach(clearWindows: Bool = false) {
        selected = nil
        if let observedPID {
            backend.endObserving(processID: observedPID)
        }
        if clearWindows { windows.removeAll() }
        observedPID = nil
    }
}
