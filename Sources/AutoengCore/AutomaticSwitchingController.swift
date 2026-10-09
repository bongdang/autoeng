@MainActor
public protocol FocusEventSource: AnyObject {
    var currentFocus: FocusContext? { get }
    var onFocusChange: (() -> Void)? { get set }
    var onProcessTermination: ((Int32) -> Void)? { get set }
    var currentApplication: FocusContext? { get }
    var onWindowFocusChange: (() -> Void)? { get set }
    var onBaselineChange: (() -> Void)? { get set }
    func isCurrent(_ context: FocusContext) -> Bool
    func synchronizeObservation()
    func start()
    func stop()
}

public extension FocusEventSource {
    var currentApplication: FocusContext? { currentFocus }
    var onWindowFocusChange: (() -> Void)? { get { nil } set {} }
    var onBaselineChange: (() -> Void)? { get { nil } set {} }
    func isCurrent(_ context: FocusContext) -> Bool { currentFocus == context }
    func synchronizeObservation() {}
}

@MainActor
public final class AutomaticSwitchingController {
    private let focus: any FocusEventSource
    private let switcher: InputSourceSwitcher
    private var policy: SwitchingPolicy
    private var isRunning = false
    private var revision: UInt64 = 0
    public private(set) var settings: AppSettings
    public var onResult: ((InputSwitchResult) -> Void)?

    public init(focus: any FocusEventSource, switcher: InputSourceSwitcher, settings: AppSettings) {
        self.focus = focus
        self.switcher = switcher
        self.settings = settings
        self.policy = SwitchingPolicy(targetBundleIDs: settings.targetBundleIDs)
        self.policy.isPaused = settings.isPaused
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        revision &+= 1
        focus.onFocusChange = { [weak self] in self?.applyCurrentFocus() }
        focus.onWindowFocusChange = { [weak self] in self?.applyCurrentFocus(windowEvent: true) }
        focus.onBaselineChange = { [weak self] in
            guard let self, self.isRunning else { return }
            self.revision &+= 1
            self.policy.synchronize(to: self.focus.currentFocus)
        }
        focus.onProcessTermination = { [weak self] pid in self?.policy.processTerminated(pid) }
        focus.start()
        applyCurrentFocus()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        revision &+= 1
        focus.stop()
        focus.onFocusChange = nil
        focus.onWindowFocusChange = nil
        focus.onBaselineChange = nil
        focus.onProcessTermination = nil
        resetPolicy()
    }

    public func updateSettings(_ settings: AppSettings) {
        guard self.settings != settings else { return }
        revision &+= 1
        let rulesChanged = self.settings.englishSourceID != settings.englishSourceID
            || self.settings.targetBundleIDs != settings.targetBundleIDs
        let resuming = self.settings.isPaused && !settings.isPaused
        self.settings = settings
        if rulesChanged || resuming { resetPolicy() }
        else { policy.isPaused = settings.isPaused }
        if isRunning && (rulesChanged || resuming) { applyCurrentFocus() }
    }

    private func resetPolicy() {
        policy = SwitchingPolicy(targetBundleIDs: settings.targetBundleIDs)
        policy.isPaused = settings.isPaused
    }

    private func applyCurrentFocus(windowEvent: Bool = false) {
        // App entry can select English before optional, potentially slow AX work.
        defer { if isRunning && !windowEvent { focus.synchronizeObservation() } }
        revision &+= 1
        let expectedRevision = revision
        let sourceBeforeQuery = switcher.currentSourceID
        let context = windowEvent ? focus.currentFocus : focus.currentApplication
        guard isRunning, policy.shouldSwitch(to: context), let context else { return }
        let result = switcher.switchToEnglish(id: settings.englishSourceID, ifStillValid: { [self] in
            isRunning && !settings.isPaused && revision == expectedRevision && focus.isCurrent(context)
                && switcher.currentSourceID == sourceBeforeQuery
        })
        onResult?(result)
    }
}
