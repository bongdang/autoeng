import Testing
@testable import AutoengCore

@MainActor
private final class FakeFocus: FocusEventSource {
    private var snapshot: FocusContext?
    var focusReads = 0
    var beforeFocusRead: (() -> Void)?
    var currentFocus: FocusContext? {
        get { focusReads += 1; beforeFocusRead?(); return snapshot }
        set { snapshot = newValue }
    }
    var currentApplication: FocusContext? { snapshot }
    var onBaselineChange: (() -> Void)?
    var onWindowFocusChange: (() -> Void)?
    func isCurrent(_ context: FocusContext) -> Bool { snapshot == context }
    var onFocusChange: (() -> Void)?
    var onProcessTermination: ((Int32) -> Void)?
    var starts = 0
    var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func emit(_ context: FocusContext?) { currentFocus = context; onFocusChange?() }
}

@MainActor
private final class AutomaticSources: InputSourceService {
    var currentSourceID: String? = "ko"
    var sources = [InputSource(id: "en", name: "ABC", languages: ["en"])]
    var selections: [String] = []
    var status: Int32 = 0
    var beforeList: (() -> Void)?
    var beforeSelection: (() -> Void)?
    func availableSources() -> [InputSource] { beforeList?(); return sources }
    func selectSource(id: String) -> Int32 {
        beforeSelection?()
        return performSelection(id: id)
    }
    func selectSource(id: String, ifStillValid: () -> Bool) -> Int32? {
        beforeSelection?()
        guard ifStillValid() else { return nil }
        return performSelection(id: id)
    }
    private func performSelection(id: String) -> Int32 {
        selections.append(id)
        if status == 0 { currentSourceID = id }
        return status
    }
}

@MainActor
struct AutomaticSwitchingTests {
    @Test func tabEventsRespectManualKoreanPauseAndStaleSelection() {
        let focus = FakeFocus(); let service = AutomaticSources(); let subject = controller(focus, service)
        func tab(_ id: Int) -> FocusContext {
            FocusContext(bundleID: "com.googlecode.iterm2", processID: 1, windowID: 1, tabID: id)
        }
        focus.currentFocus = tab(1); subject.start()
        service.currentSourceID = "ko"
        focus.onWindowFocusChange?()
        #expect(service.currentSourceID == "ko")
        focus.currentFocus = tab(2); focus.onWindowFocusChange?()
        #expect(service.currentSourceID == "en")
        service.currentSourceID = "ko"
        focus.onWindowFocusChange?()
        #expect(service.currentSourceID == "ko")
        focus.currentFocus = tab(3)
        service.beforeSelection = { focus.currentFocus = tab(4) }
        focus.onWindowFocusChange?()
        #expect(service.currentSourceID == "ko")
        service.beforeSelection = nil
        focus.onBaselineChange?()
        focus.currentFocus = tab(5); focus.onWindowFocusChange?()
        #expect(service.currentSourceID == "en")
        var paused = subject.settings; paused.isPaused = true; subject.updateSettings(paused)
        service.currentSourceID = "ko"; focus.currentFocus = tab(6); focus.onWindowFocusChange?()
        #expect(service.currentSourceID == "ko")
    }
    private let target = FocusContext(bundleID: "com.apple.Terminal", processID: 1)
    private let other = FocusContext(bundleID: "com.apple.Safari", processID: 2)

    private func controller(_ focus: FakeFocus, _ service: AutomaticSources,
                            settings: AppSettings = AppSettings(englishSourceID: "en")) -> AutomaticSwitchingController {
        AutomaticSwitchingController(focus: focus, switcher: InputSourceSwitcher(service: service), settings: settings)
    }

    @Test func appEntryDoesNotWaitForWindowLookup() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start()
        #expect(service.selections == ["en"])
        #expect(focus.focusReads == 0)
    }

    @Test func manualSourceChangeDuringWindowQueryCancelsSelection() {
        let focus = FakeFocus(); let service = AutomaticSources(); let subject = controller(focus, service)
        focus.currentFocus = FocusContext(bundleID: target.bundleID, processID: 1, windowID: 1)
        subject.start()
        service.currentSourceID = "ko"
        focus.currentFocus = FocusContext(bundleID: target.bundleID, processID: 1, windowID: 2)
        focus.beforeFocusRead = { service.currentSourceID = "manual" }
        focus.onWindowFocusChange?()
        #expect(service.selections == ["en"])
        #expect(service.currentSourceID == "manual")
    }

    @Test func baselineRefreshPreservesKoreanThenRealWindowMoveSwitches() {
        let focus = FakeFocus(); let service = AutomaticSources(); let subject = controller(focus, service)
        let a = FocusContext(bundleID: target.bundleID, processID: 1, windowID: 1)
        let b = FocusContext(bundleID: target.bundleID, processID: 1, windowID: 2)
        let c = FocusContext(bundleID: target.bundleID, processID: 1, windowID: 3)
        focus.currentFocus = a; subject.start()
        service.currentSourceID = "ko"
        focus.currentFocus = b; focus.onBaselineChange?()
        #expect(service.currentSourceID == "ko")
        focus.currentFocus = c; focus.onWindowFocusChange?()
        #expect(service.currentSourceID == "en")
        #expect(service.selections == ["en", "en"])
        subject.stop()
        #expect(focus.onBaselineChange == nil)
        #expect(focus.onWindowFocusChange == nil)
    }

    @Test(arguments: ["list", "selection"])
    func foregroundChangeDuringPreparationCancelsSelection(stage: String) {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources()
        let move = { focus.currentFocus = self.other }
        if stage == "list" { service.beforeList = move } else { service.beforeSelection = move }
        let subject = controller(focus, service)
        subject.start()
        #expect(service.selections.isEmpty)
        #expect(service.currentSourceID == "ko")
        service.beforeList = nil; service.beforeSelection = nil
        focus.emit(other); focus.emit(target)
        #expect(service.selections == ["en"])
    }

    @Test func stopDuringPreparationCancelsSelection() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources(); let subject = controller(focus, service)
        service.beforeList = { subject.stop() }
        subject.start()
        #expect(service.selections.isEmpty)
    }

    @Test func pauseDuringPreparationCancelsSelection() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources(); let subject = controller(focus, service)
        service.beforeList = { var paused = subject.settings; paused.isPaused = true; subject.updateSettings(paused) }
        subject.start()
        #expect(service.selections.isEmpty)
    }

    @Test func manualSourceChangeDuringPreparationCancelsSelection() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources()
        service.beforeList = { service.currentSourceID = "manual" }
        let subject = controller(focus, service); subject.start()
        #expect(service.selections.isEmpty)
        #expect(service.currentSourceID == "manual")
    }

    @Test func startupInTargetAppliesExactlyOnce() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start(); subject.start()
        #expect(service.selections == ["en"])
        #expect(focus.starts == 1)
    }

    @Test func nonTargetAndMissingFocusDoNotSelect() {
        let focus = FakeFocus(); focus.currentFocus = other
        let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start(); focus.emit(nil); focus.emit(other)
        #expect(service.selections.isEmpty)
    }

    @Test func enteringTargetAndReturningApplyRule() {
        let focus = FakeFocus(); let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start(); focus.emit(target)
        service.currentSourceID = "ko"
        focus.emit(other); focus.emit(target)
        #expect(service.selections == ["en", "en"])
    }

    @Test func duplicateEventRespectsManualKorean() {
        let focus = FakeFocus(); let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start(); focus.emit(target)
        service.currentSourceID = "ko"
        focus.emit(target)
        #expect(service.selections == ["en"])
        #expect(service.currentSourceID == "ko")
    }

    @Test func sameBundleDifferentPIDIsNewEntry() {
        let focus = FakeFocus(); let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start(); focus.emit(target)
        service.currentSourceID = "ko"
        focus.emit(FocusContext(bundleID: target.bundleID, processID: 3))
        #expect(service.selections == ["en", "en"])
    }

    @Test func disabledTargetAndSavedPauseSuppressSwitches() {
        let focus = FakeFocus(); let service = AutomaticSources()
        let subject = controller(focus, service, settings: AppSettings(englishSourceID: "en", targetBundleIDs: []))
        subject.start(); focus.emit(target)
        subject.updateSettings(AppSettings(englishSourceID: "en", isPaused: true))
        focus.emit(other); focus.emit(target)
        #expect(service.selections.isEmpty)
    }

    @Test func resumeInCurrentTargetAppliesOnceAndUpdatesSettings() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources()
        let subject = controller(focus, service, settings: AppSettings(englishSourceID: "en", isPaused: true))
        subject.start()
        #expect(service.selections.isEmpty)
        subject.updateSettings(AppSettings(englishSourceID: "en")); focus.emit(target)
        #expect(service.selections == ["en"])
        #expect(!subject.settings.isPaused)
    }

    @Test func resumeInOtherAppDoesNotSelectUntilTargetEntry() {
        let focus = FakeFocus(); focus.currentFocus = other
        let service = AutomaticSources()
        let subject = controller(focus, service, settings: AppSettings(englishSourceID: "en", isPaused: true))
        subject.start(); subject.updateSettings(AppSettings(englishSourceID: "en"))
        #expect(service.selections.isEmpty)
        focus.emit(target)
        #expect(service.selections == ["en"])
    }

    @Test(arguments: ["missing", "unconfigured", "failure"])
    func errorsReachUIWithoutRetryOrFallback(kind: String) {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources()
        if kind == "missing" { service.sources = [] }
        if kind == "failure" { service.status = -50 }
        let subject = controller(focus, service, settings: AppSettings(englishSourceID: kind == "unconfigured" ? nil : "en"))
        var results: [InputSwitchResult] = []
        subject.onResult = { results.append($0) }
        subject.start(); focus.emit(target)
        let expected: InputSwitchResult = kind == "missing" ? .unavailable("en") : (kind == "failure" ? .selectionFailed(-50) : .noTarget)
        #expect(results == [expected])
        #expect(service.selections.count == (kind == "failure" ? 1 : 0))
    }

    @Test func enablingTargetOrChoosingSourceAppliesCurrentRule() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources()
        let subject = controller(focus, service, settings: AppSettings(targetBundleIDs: []))
        subject.start(); subject.updateSettings(AppSettings(englishSourceID: "en"))
        #expect(service.selections == ["en"])
    }

    @Test func identicalSettingsDoNotOverrideManualKorean() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start(); service.currentSourceID = "ko"
        subject.updateSettings(subject.settings)
        #expect(service.selections == ["en"])
        #expect(service.currentSourceID == "ko")
    }

    @Test func stopUnsubscribesAndRestartIsFreshEntry() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start(); subject.stop(); subject.stop()
        #expect(focus.onFocusChange == nil)
        #expect(focus.onProcessTermination == nil)
        #expect(focus.stops == 1)
        service.currentSourceID = "ko"; focus.emit(target)
        #expect(service.selections == ["en"])
        subject.start()
        #expect(service.selections == ["en", "en"])
    }

    @Test func processTerminationClearsStaleFocus() {
        let focus = FakeFocus(); focus.currentFocus = target
        let service = AutomaticSources(); let subject = controller(focus, service)
        subject.start(); service.currentSourceID = "ko"
        focus.onProcessTermination?(1); focus.emit(target)
        #expect(service.selections == ["en", "en"])
    }
}
