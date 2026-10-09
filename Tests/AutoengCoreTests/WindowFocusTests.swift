import Testing
@testable import AutoengCore

private final class ReferenceWindow: Equatable {
    let identity: Int
    init(_ identity: Int) { self.identity = identity }
    static func == (lhs: ReferenceWindow, rhs: ReferenceWindow) -> Bool { lhs.identity == rhs.identity }
}

@MainActor
private final class ReferenceBackend: WindowObservationBackend {
    var isTrusted = true
    var window: ReferenceWindow?
    var tab: ReferenceWindow?
    var windowReadStatus: WindowObservationStatus = .available
    func selectedTab(processID: Int32, window: ReferenceWindow) -> ReferenceWindow? { tab }
    func beginObserving(processID: Int32) -> WindowObservationStatus { .available }
    func endObserving(processID: Int32) {}
    func focusedWindow(processID: Int32) -> ReferenceWindow? { window }
}

@MainActor
private final class WindowBackend: WindowObservationBackend {
    // Equality represents AX object identity, never a window title.
    struct Window: Equatable {
        let identity: Int; let title: String
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
    }
    var isTrusted = true
    var result: WindowObservationStatus = .available
    var window: Window? = Window(identity: 1, title: "same title")
    var starts: [Int32] = []
    var stops: [Int32] = []
    var reads = 0
    var windowReadStatus: WindowObservationStatus = .available
    var requiresWindowReconciliation = false
    var liveWindows: [Window]?
    var tab: Window?
    func selectedTab(processID: Int32, window: Window) -> Window? { tab }
    func existingWindows(processID: Int32) -> [Window]? { liveWindows }
    func beginObserving(processID: Int32) -> WindowObservationStatus { starts.append(processID); return result }
    func endObserving(processID: Int32) { stops.append(processID) }
    func focusedWindow(processID: Int32) -> Window? { reads += 1; return window }
}

@MainActor
struct WindowFocusTests {
    private let app = FocusContext(bundleID: "terminal", processID: 1)
    private let targets: Set<String> = ["terminal"]

    @Test(arguments: ["changed", "readError", "permission", "destroyed", "otherApp", "stop"])
    func retiredTabReferenceIsReleased(reason: String) {
        let backend = ReferenceBackend(); let resolver = WindowFocusResolver(backend: backend)
        backend.window = ReferenceWindow(1)
        var tab: ReferenceWindow? = ReferenceWindow(100)
        weak var retired = tab
        backend.tab = tab
        _ = resolver.resolve(app, targets: targets)
        backend.tab = nil; tab = nil
        switch reason {
        case "changed": backend.tab = ReferenceWindow(101); _ = resolver.resolve(app, targets: targets)
        case "readError": backend.windowReadStatus = .failed(-25204); _ = resolver.resolve(app, targets: targets)
        case "permission": backend.isTrusted = false; _ = resolver.resolve(app, targets: targets)
        case "destroyed": resolver.windowDestroyed(backend.window!, processID: 1)
        case "otherApp": _ = resolver.resolve(FocusContext(bundleID: "browser", processID: 2), targets: targets)
        default: resolver.stop()
        }
        #expect(retired == nil)
    }

    @Test func selectedTabHasStableIdentityAndDifferentTabChangesContext() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        backend.tab = .init(identity: 101, title: "same")
        let first = resolver.resolve(app, targets: targets)
        #expect(first?.tabID != nil)
        backend.tab = .init(identity: 101, title: "renamed")
        #expect(resolver.resolve(app, targets: targets) == first)
        backend.tab = .init(identity: 102, title: "same")
        let second = resolver.resolve(app, targets: targets)
        #expect(second?.windowID == first?.windowID)
        #expect(second?.tabID != first?.tabID)
    }

    @Test func incompleteWindowListDoesNotInventAnotherFocusBoundary() {
        let backend = WindowBackend(); backend.requiresWindowReconciliation = true; backend.liveWindows = []
        let resolver = WindowFocusResolver(backend: backend)
        let first = resolver.resolve(app, targets: targets)
        #expect(resolver.resolve(app, targets: targets) == first)
    }

    @Test(arguments: ["destroyed", "otherApp", "otherPID", "stop"])
    func retiredWindowReferencesAreReleased(reason: String) {
        let backend = ReferenceBackend(); let resolver = WindowFocusResolver(backend: backend)
        var window: ReferenceWindow? = ReferenceWindow(1)
        weak var retired = window
        backend.window = window
        _ = resolver.resolve(app, targets: targets)
        backend.window = nil
        switch reason {
        case "destroyed": resolver.windowDestroyed(window!, processID: 1)
        case "otherApp": _ = resolver.resolve(FocusContext(bundleID: "browser", processID: 2), targets: targets)
        case "otherPID": _ = resolver.resolve(FocusContext(bundleID: "terminal", processID: 2), targets: targets)
        default: resolver.stop()
        }
        window = nil
        #expect(retired == nil)
    }

    @Test func destroyedWindowIsForgottenAndOtherLiveTokenPreserved() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        let a = backend.window!
        let first = resolver.resolve(app, targets: targets)
        backend.window = .init(identity: 2, title: "B")
        let second = resolver.resolve(app, targets: targets)
        resolver.windowDestroyed(a, processID: 999) // Stale notification from another PID.
        backend.window = a
        #expect(resolver.resolve(app, targets: targets) == first)
        resolver.windowDestroyed(a, processID: 1)
        #expect(resolver.resolve(app, targets: targets)?.windowID != first?.windowID)
        backend.window = .init(identity: 2, title: "renamed B")
        #expect(resolver.resolve(app, targets: targets) == second)
    }

    @Test func successfulLiveWindowReconciliationPrunesOnlyClosedWindows() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        let a = backend.window!
        let first = resolver.resolve(app, targets: targets)
        backend.window = .init(identity: 2, title: "B")
        let second = resolver.resolve(app, targets: targets)
        backend.liveWindows = nil; resolver.pruneClosedWindows(processID: 1)
        backend.window = a
        #expect(resolver.resolve(app, targets: targets) == first)
        backend.liveWindows = [.init(identity: 2, title: "B")]
        resolver.pruneClosedWindows(processID: 1)
        #expect(resolver.resolve(app, targets: targets)?.windowID != first?.windowID)
        backend.window = .init(identity: 2, title: "B")
        #expect(resolver.resolve(app, targets: targets) == second)
    }

    @Test func failedFocusedWindowReadReportsFailureAndRecoveryRestoresStatus() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        _ = resolver.resolve(app, targets: targets)
        backend.window = nil; backend.windowReadStatus = .failed(-25204)
        #expect(resolver.resolve(app, targets: targets)?.windowID == nil)
        #expect(resolver.status == .failed(-25204))
        backend.window = .init(identity: 1, title: "A"); backend.windowReadStatus = .available
        #expect(resolver.resolve(app, targets: targets)?.windowID != nil)
        #expect(resolver.status == .available)
    }

    @Test(arguments: [true, false])
    func differentWindowAfterObservationGapDoesNotOverrideKorean(permissionGap: Bool) {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        var policy = SwitchingPolicy(targetBundleIDs: targets)
        let entered = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        #expect(entered)
        if permissionGap { backend.isTrusted = false } else { backend.window = nil }
        let missing = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        #expect(!missing)
        backend.isTrusted = true; backend.window = .init(identity: 2, title: "B")
        let recovered = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        #expect(!recovered)
        backend.window = .init(identity: 3, title: "C")
        let moved = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        #expect(moved)
    }

    @Test func distinctWindowsWithSameTitleHaveDifferentStableTokens() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        let first = resolver.resolve(app, targets: targets)
        let duplicate = resolver.resolve(app, targets: targets)
        backend.window = .init(identity: 2, title: "same title")
        let second = resolver.resolve(app, targets: targets)
        backend.window = .init(identity: 1, title: "same title")
        let returned = resolver.resolve(app, targets: targets)
        #expect(first?.windowID != nil)
        #expect(first == duplicate)
        #expect(first?.windowID != second?.windowID)
        #expect(first == returned)
        #expect(backend.starts == [1])
    }

    @Test func noPermissionMaintainsAppContextWithoutAXCalls() {
        let backend = WindowBackend(); backend.isTrusted = false
        let resolver = WindowFocusResolver(backend: backend)
        #expect(resolver.resolve(app, targets: targets) == app)
        #expect(resolver.status == .permissionRequired)
        #expect(backend.starts.isEmpty)
        #expect(backend.reads == 0)
    }

    @Test func revocationStopsObserverAndRecoveryPreservesWindowToken() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        let first = resolver.resolve(app, targets: targets)
        backend.isTrusted = false
        #expect(resolver.resolve(app, targets: targets)?.windowID == nil)
        #expect(backend.stops == [1])
        #expect(resolver.status == .permissionRequired)
        backend.isTrusted = true
        #expect(resolver.resolve(app, targets: targets) == first)
        #expect(backend.starts == [1, 1])
        #expect(resolver.status == .available)
    }

    @Test(arguments: [WindowObservationStatus.unsupported, .failed(-25204)])
    func failedSubscriptionKeepsAppOnlyAndReportsStatus(status: WindowObservationStatus) {
        let backend = WindowBackend(); backend.result = status
        let resolver = WindowFocusResolver(backend: backend)
        #expect(resolver.resolve(app, targets: targets) == app)
        #expect(resolver.status == status)
        #expect(backend.reads == 0)
    }

    @Test func nonTargetAndMissingForegroundReleaseObservation() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        _ = resolver.resolve(app, targets: targets)
        let other = FocusContext(bundleID: "browser", processID: 2)
        #expect(resolver.resolve(other, targets: targets) == other)
        #expect(backend.stops == [1])
        #expect(backend.reads == 1)
        #expect(resolver.resolve(nil, targets: targets) == nil)
    }

    @Test func differentProcessReattachesAndDoesNotReuseWindowIdentity() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        let first = resolver.resolve(app, targets: targets)
        let second = resolver.resolve(FocusContext(bundleID: "terminal", processID: 2), targets: targets)
        #expect(first?.windowID != second?.windowID)
        #expect(backend.stops == [1])
        #expect(backend.starts == [1, 2])
    }

    @Test func missingWindowDoesNotInventIdentityOrOverrideKoreanPolicy() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        var policy = SwitchingPolicy(targetBundleIDs: targets)
        let initial = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        backend.window = nil
        let missing = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        backend.window = .init(identity: 1, title: "same title")
        let restored = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        backend.window = .init(identity: 2, title: "same title")
        let moved = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        #expect(initial)
        #expect(!missing)
        #expect(!restored)
        #expect(moved)
    }

    @Test func lateWindowDiscoveryIsNotAnotherAppEntry() {
        let backend = WindowBackend(); backend.window = nil
        let resolver = WindowFocusResolver(backend: backend)
        var policy = SwitchingPolicy(targetBundleIDs: targets)
        let initial = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        backend.window = .init(identity: 1, title: "same title")
        let discovered = policy.shouldSwitch(to: resolver.resolve(app, targets: targets))
        #expect(initial)
        #expect(!discovered)
    }

    @Test func terminatedProcessClearsTokensAndObserver() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        let first = resolver.resolve(app, targets: targets)
        resolver.processTerminated(1)
        let second = resolver.resolve(app, targets: targets)
        #expect(first?.windowID != second?.windowID)
        #expect(backend.stops == [1])
        resolver.stop(); resolver.stop()
        #expect(backend.stops == [1, 1])
    }

    @Test func backgroundAndStaleWindowEventsAreIgnored() {
        let backend = WindowBackend(); let resolver = WindowFocusResolver(backend: backend)
        _ = resolver.resolve(app, targets: targets)
        #expect(resolver.acceptsWindowEvent(processID: 1, foreground: app))
        #expect(!resolver.acceptsWindowEvent(processID: 2, foreground: app))
        #expect(!resolver.acceptsWindowEvent(processID: 1, foreground: FocusContext(bundleID: "browser", processID: 2)))
        #expect(!resolver.acceptsWindowEvent(processID: 1, foreground: nil))
        backend.isTrusted = false
        #expect(!resolver.acceptsWindowEvent(processID: 1, foreground: app))
    }
}
