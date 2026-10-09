import AppKit
import AutoengCore

@MainActor
final class WorkspaceFocusMonitor: FocusEventSource {
    var onFocusChange: (() -> Void)?
    var onProcessTermination: ((Int32) -> Void)?
    var onWindowFocusChange: (() -> Void)?
    var onBaselineChange: (() -> Void)?
    var onWindowStatusChange: (() -> Void)?
    private let windowBackend = AccessibilityWindowBackend()
    private lazy var windows = WindowFocusResolver(backend: windowBackend)
    private var targetIDs: Set<String> = ["com.googlecode.iterm2", "com.apple.Terminal"]
    private var permissionTimer: Timer?
    private var lastTrusted = false
    private var tokens: [NSObjectProtocol] = []

    var currentFocus: FocusContext? {
        let oldStatus = windows.status
        let result = windows.resolve(foregroundApplication, targets: targetIDs)
        if oldStatus != windows.status { onWindowStatusChange?() }
        // Other processes can change foreground state while AX IPC blocks our main actor.
        guard let result, let foreground = foregroundApplication,
              result.processID == foreground.processID, result.bundleID == foreground.bundleID else { return nil }
        return result
    }

    var windowStatus: WindowObservationStatus { windows.status }
    var currentApplication: FocusContext? { foregroundApplication }

    func isCurrent(_ context: FocusContext) -> Bool {
        guard let foreground = foregroundApplication,
              foreground.processID == context.processID, foreground.bundleID == context.bundleID else { return false }
        return context.windowID == nil || currentFocus == context
    }

    func synchronizeObservation() {
        if let onBaselineChange { onBaselineChange() }
        else { _ = currentFocus }
    }

    private var foregroundApplication: FocusContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier else { return nil }
        return FocusContext(bundleID: id, processID: app.processIdentifier)
    }

    func start() {
        guard tokens.isEmpty else { return }
        lastTrusted = windowBackend.isTrusted
        windowBackend.onWindowDestroyed = { [weak self] window, pid in
            self?.windows.windowDestroyed(window, processID: pid)
        }
        windowBackend.onWindowChange = { [weak self] pid in
            guard let self, self.windows.acceptsWindowEvent(processID: pid, foreground: self.foregroundApplication) else { return }
            self.onWindowFocusChange?()
        }
        // Only watch permission changes. This timer never polls windows or forces English.
        permissionTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lastTrusted != self.windowBackend.isTrusted else { return }
                self.refreshPermissions()
            }
        }
        if let permissionTimer { RunLoop.main.add(permissionTimer, forMode: .common) }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Read current foreground state rather than trusting a stale notification.
                self?.onFocusChange?()
            }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                         object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.windows.processTerminated(pid)
                self?.onProcessTermination?(pid)
            }
        })
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        windows.stop()
        windowBackend.onWindowChange = nil
        windowBackend.onWindowDestroyed = nil
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }

    func updateTargets(_ targets: Set<String>) {
        guard targetIDs != targets else { return }
        targetIDs = targets
        if !tokens.isEmpty { synchronizeObservation() }
    }

    func refreshPermissions() {
        lastTrusted = windowBackend.isTrusted
        synchronizeObservation()
    }

    func requestWindowPermission() { windowBackend.requestPermission() }
}
