import AppKit
import ApplicationServices
import AutoengCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let smokeTest: Bool
    private let verifyInputSwitch: Bool
    private let verifyAppActivation: Bool
    private let verifyWindowSwitch: Bool
    private let verifyTabSwitch: Bool
    private let smokeSuite: String?
    private let defaults: UserDefaults
    private let store: SettingsStore
    private let service = CarbonInputSourceService()
    private lazy var switcher = InputSourceSwitcher(service: service)
    private let focusMonitor = WorkspaceFocusMonitor()
    private lazy var automatic = AutomaticSwitchingController(
        focus: focusMonitor, switcher: switcher, settings: settings
    )
    private var settings: AppSettings
    private var statusItem: NSStatusItem?
    private var lastMessage: String?
    private var automaticResultCount = 0

    init(smokeTest: Bool = false, verifyInputSwitch: Bool = false, verifyAppActivation: Bool = false,
         verifyWindowSwitch: Bool = false, verifyTabSwitch: Bool = false) {
        self.smokeTest = smokeTest
        self.verifyInputSwitch = verifyInputSwitch
        self.verifyAppActivation = verifyAppActivation
        self.verifyWindowSwitch = verifyWindowSwitch
        self.verifyTabSwitch = verifyTabSwitch
        let suite = smokeTest ? "local.autoeng.smoke.\(UUID().uuidString)" : nil
        self.smokeSuite = suite
        let defaults = suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        let store = SettingsStore(defaults: defaults)
        self.store = store
        self.settings = store.load()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 30)
        item.button?.image = StatusIcon.make()
        item.button?.setAccessibilityLabel("Auto Eng")
        item.button?.toolTip = "Autoeng"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
        focusMonitor.updateTargets(settings.targetBundleIDs)
        focusMonitor.onWindowStatusChange = { [weak self] in
            guard let self, let menu = self.statusItem?.menu else { return }
            self.rebuildMenu(menu)
        }
        rebuildMenu(menu)
        automatic.onResult = { [weak self] result in
            guard let self else { return }
            self.automaticResultCount += 1
            self.displayResult(result)
        }
        if smokeTest {
            runSmokeTest(menu)
            if verifyAppActivation || verifyWindowSwitch || verifyTabSwitch {
                Task {
                    if verifyAppActivation { await verifyRealAppActivation() }
                    if verifyWindowSwitch { await verifyRealWindowSwitch() }
                    if verifyTabSwitch { await verifyRealTabSwitch() }
                    quitApplication()
                }
            } else { quitApplication() }
        } else {
            automatic.start()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        focusMonitor.refreshPermissions()
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        addLabel("Autoeng", to: menu)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        addLabel("Version: \(version)", to: menu)
        let state = settings.isPaused ? "Paused" : (settings.englishSourceID == nil ? "Choose an English input source" : "Running")
        addLabel("Automatic switching: \(state)", to: menu)
        switch focusMonitor.windowStatus {
        case .available: addLabel("Window detection: Available", to: menu)
        case .permissionRequired: addLabel("Window detection: Accessibility permission required", to: menu)
        case .unsupported: addLabel("Window detection: Notifications unsupported by this app", to: menu)
        case .failed(let code): addLabel("Window detection: Connection failed (\(code))", to: menu)
        }
        menu.addItem(actionItem("Accessibility settings…", action: #selector(openWindowPermissionSettings)))
        addLabel("Current input: \(service.currentSourceName ?? "Unknown")", to: menu)
        let candidates = switcher.englishSources
        let targetName = candidates.first(where: { $0.id == settings.englishSourceID })?.name
        let targetLabel = settings.englishSourceID == nil ? "Not selected" : (targetName ?? "Unavailable source")
        let picker = NSMenuItem(title: "English input source: \(targetLabel)", action: nil, keyEquivalent: "")
        let choices = NSMenu()
        choices.autoenablesItems = false
        for source in candidates {
            let choice = actionItem(source.name, action: #selector(selectEnglishSource(_:)))
            choice.representedObject = source.id
            choice.state = source.id == settings.englishSourceID ? .on : .off
            choices.addItem(choice)
        }
        if candidates.isEmpty { addLabel("No English input sources available", to: choices) }
        picker.submenu = choices
        menu.addItem(picker)
        let manual = actionItem("Switch to English", action: #selector(switchManually))
        manual.isEnabled = settings.englishSourceID != nil
        menu.addItem(manual)
        if let lastMessage { addLabel("Recent result: \(lastMessage)", to: menu) }
        menu.addItem(actionItem(settings.isPaused ? "Resume automatic switching" : "Pause automatic switching",
                                action: #selector(togglePause)))
        menu.addItem(.separator())
        let targets = NSMenuItem(title: "Target apps", action: nil, keyEquivalent: "")
        let targetMenu = NSMenu()
        targetMenu.autoenablesItems = false
        for (name, id) in [("iTerm2", "com.googlecode.iterm2"), ("Terminal", "com.apple.Terminal")] {
            let choice = actionItem(name, action: #selector(toggleTarget(_:)))
            choice.representedObject = id
            choice.state = settings.targetBundleIDs.contains(id) ? .on : .off
            targetMenu.addItem(choice)
        }
        targets.submenu = targetMenu
        menu.addItem(targets)
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Autoeng", action: #selector(quitApplication), key: "q"))
    }

    private func addLabel(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func actionItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func save(_ updated: AppSettings) {
        do {
            try store.save(updated)
            settings = updated
            lastMessage = nil
            focusMonitor.updateTargets(updated.targetBundleIDs)
            automatic.updateSettings(updated)
        } catch { lastMessage = "Could not save settings" }
        if let menu = statusItem?.menu { rebuildMenu(menu) }
    }

    @objc private func selectEnglishSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        guard switcher.englishSources.contains(where: { $0.id == id }) else {
            lastMessage = "The selected English input source is unavailable"
            if let menu = statusItem?.menu { rebuildMenu(menu) }
            return
        }
        var updated = settings
        updated.englishSourceID = id
        save(updated)
    }

    @objc private func toggleTarget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var updated = settings
        if updated.targetBundleIDs.contains(id) { updated.targetBundleIDs.remove(id) }
        else { updated.targetBundleIDs.insert(id) }
        save(updated)
    }

    @objc private func switchManually() {
        displayResult(switcher.switchToEnglish(id: settings.englishSourceID))
    }

    @objc private func togglePause() {
        var updated = settings
        updated.isPaused.toggle()
        save(updated)
    }

    @objc private func openWindowPermissionSettings() {
        focusMonitor.requestWindowPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func displayResult(_ result: InputSwitchResult) {
        switch result {
        case .switched: lastMessage = "Switched to English"
        case .alreadySelected: lastMessage = "English is already selected"
        case .cancelled: lastMessage = "Input switching skipped because the context changed"
        case .noTarget: lastMessage = "Choose an English input source first"
        case .unavailable: lastMessage = "The saved input source is missing. Choose another source"
        case .ineligible: lastMessage = "The saved English input source cannot be used"
        case .selectionFailed(let code): lastMessage = "Input switching failed (\(code))"
        case .verificationFailed: lastMessage = "The input source did not change. Check its status"
        }
        if let menu = statusItem?.menu { rebuildMenu(menu) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        automatic.stop()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        if let smokeSuite { defaults.removePersistentDomain(forName: smokeSuite) }
        if smokeTest { print("PASS: termination and status item cleanup") }
    }

    @objc private func quitApplication() { NSApplication.shared.terminate(nil) }

    private func runSmokeTest(_ menu: NSMenu) {
        guard let icon = statusItem?.button?.image, icon.isTemplate,
              icon.size == NSSize(width: 30, height: 22), statusItem?.menu === menu,
              NSApplication.shared.activationPolicy() == .accessory,
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty,
              menu.items.contains(where: { $0.title == "Version: \(version)" }),
              service.currentSourceID != nil,
              let quit = menu.items.last, quit.target === self,
              quit.action == #selector(quitApplication),
              let picker = menu.items.first(where: { $0.submenu?.items.first?.action == #selector(selectEnglishSource(_:)) }),
              let choice = picker.submenu?.items.first,
              let selectedID = choice.representedObject as? String else {
            failSmoke("launch, menu or English source enumeration")
        }
        selectEnglishSource(choice)
        guard settings.englishSourceID == selectedID,
              SettingsStore(defaults: defaults).load() == settings,
              menu.items.contains(where: { $0.action == #selector(switchManually) && $0.isEnabled }) else {
            failSmoke("source choice and settings persistence")
        }
        print("PASS: launch, menu source choice, settings reload, manual action, Carbon lookup")
        if CommandLine.arguments.contains("--export-icon-preview") {
            do {
                try StatusIcon.exportPreview(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("build/status-icon.png"))
                print("PASS: Auto Eng two-line template icon and preview export")
            } catch { failSmoke("icon preview export: \(error)") }
        }
        if verifyInputSwitch { verifyRealInputSwitch(englishID: selectedID) }
    }

    private func verifyRealInputSwitch(englishID: String) {
        guard let original = service.currentSourceID,
              let korean = service.availableSources().first(where: {
                  $0.isKeyboard && $0.isEnabled && $0.isSelectable && $0.languages.contains("ko")
              }) else { failSmoke("Korean input source required for integration check") }
        var failure: String?
        if service.selectSource(id: korean.id) != 0 || service.currentSourceID != korean.id {
            failure = "select Korean source"
        } else {
            switchManually()
            if service.currentSourceID != englishID || lastMessage != "Switched to English" {
                failure = "manual Korean to English transition"
            }
        }
        let restored = service.selectSource(id: original) == 0 && service.currentSourceID == original
        if !restored { failSmoke("restore original input source") }
        if let failure { failSmoke(failure) }
        print("PASS: actual Korean to English menu action and original source restoration")
    }

    private func verifyRealAppActivation() async {
        let workspace = NSWorkspace.shared
        guard let originalSource = service.currentSourceID,
              let english = settings.englishSourceID,
              let target = workspace.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.googlecode.iterm2" || $0.bundleIdentifier == "com.apple.Terminal"
              }),
              let targetID = target.bundleIdentifier,
              let finder = workspace.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }),
              let korean = service.availableSources().first(where: {
                  $0.isKeyboard && $0.isEnabled && $0.isSelectable && $0.languages.contains("ko")
              }) else { failSmoke("running terminal, Finder, English and Korean sources required") }
        let originalApp = workspace.frontmostApplication
        save(AppSettings(englishSourceID: english, targetBundleIDs: [targetID], isPaused: true))
        automatic.start()
        let failure = await exerciseAutomaticSwitching(target: target, other: finder, koreanID: korean.id, englishID: english)
        automatic.stop()
        var restoredApp = true
        if let originalApp {
            _ = originalApp.activate(options: [.activateIgnoringOtherApps])
            restoredApp = await waitUntil { workspace.frontmostApplication?.processIdentifier == originalApp.processIdentifier }
        }
        // Allow document input-source restoration to settle before restoring the original source.
        try? await Task.sleep(for: .milliseconds(100))
        let restoredSource = service.selectSource(id: originalSource) == 0 && service.currentSourceID == originalSource
        if !restoredSource || !restoredApp { failSmoke("restore original app and input source") }
        if let failure { failSmoke(failure) }
        print("PASS: actual terminal activation, manual Korean preserved, pause/resume, original app and source restored")
    }

    private func exerciseAutomaticSwitching(target: NSRunningApplication, other: NSRunningApplication,
                                             koreanID: String, englishID: String) async -> String? {
        guard other.activate(options: [.activateIgnoringOtherApps]),
              await waitUntil({ NSWorkspace.shared.frontmostApplication?.processIdentifier == other.processIdentifier }) else {
            return "activate non-target app"
        }
        togglePause() // Resume while the non-target is foreground.
        guard service.selectSource(id: koreanID) == 0, service.currentSourceID == koreanID else { return "select Korean before entry" }
        let countBeforeEntry = automaticResultCount
        guard target.activate(options: [.activateIgnoringOtherApps]),
              await waitUntil({ NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
                  && self.automaticResultCount > countBeforeEntry && self.service.currentSourceID == englishID }) else { return "automatic English on actual terminal entry" }
        guard service.selectSource(id: koreanID) == 0 else { return "manual Korean selection" }
        try? await Task.sleep(for: .milliseconds(150))
        guard service.currentSourceID == koreanID else { return "manual Korean was overridden" }
        togglePause()
        guard settings.isPaused, store.load().isPaused else { return "saved pause state" }
        guard other.activate(options: [.activateIgnoringOtherApps]),
              await waitUntil({ NSWorkspace.shared.frontmostApplication?.processIdentifier == other.processIdentifier }) else { return "leave paused terminal" }
        guard service.selectSource(id: koreanID) == 0 else { return "Korean before paused entry" }
        guard target.activate(options: [.activateIgnoringOtherApps]),
              await waitUntil({ NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier }) else { return "paused terminal entry" }
        try? await Task.sleep(for: .milliseconds(150))
        guard service.currentSourceID == koreanID else { return "paused entry changed input source" }
        togglePause()
        guard !settings.isPaused, !store.load().isPaused, service.currentSourceID == englishID else { return "resume in target" }
        return nil
    }

    private func verifyRealWindowSwitch() async {
        guard AXIsProcessTrusted() else {
            skipSmoke("actual window switching requires Autoeng Accessibility permission")
        }
        guard let originalSource = service.currentSourceID, let english = settings.englishSourceID,
              let target = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }),
              let id = target.bundleIdentifier,
              let korean = service.availableSources().first(where: { $0.isKeyboard && $0.isEnabled && $0.isSelectable && $0.languages.contains("ko") }) else {
            failSmoke("running iTerm2 and input sources required")
        }
        let inspection = AccessibilityWindowInspection(processID: target.processIdentifier)
        let verification = WindowSwitchVerification(backend: inspection)
        let list: [AccessibilityWindow]
        let originalWindow: AccessibilityWindow
        switch verification.prepare() {
        case .insufficientWindows: skipSmoke("actual window switching requires two existing iTerm2 windows")
        case .failed(let error): failSmoke("prepare window verification: \(error)")
        case .ready(let windows, let original): list = windows; originalWindow = original
        }
        guard let originalApp = NSWorkspace.shared.frontmostApplication else { failSmoke("capture original foreground app") }
        save(AppSettings(englishSourceID: english, targetBundleIDs: [id]))
        automatic.start()
        _ = target.activate(options: [.activateIgnoringOtherApps])
        var failure: String?
        if !(await waitUntil({ NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier })) {
            failure = "activate iTerm2 for window verification"
        } else if case .failure(let error) = await verification.restore(list[0]) {
            failure = "focus first iTerm2 window: \(error)"
        } else if !(await waitUntil({ self.focusMonitor.currentFocus?.windowID != nil })) {
            failure = "query focused iTerm2 window"
        } else {
            try? await Task.sleep(for: .milliseconds(150))
            let firstToken = focusMonitor.currentFocus?.windowID
            let countBeforeMove = automaticResultCount
            if service.selectSource(id: korean.id) != 0 { failure = "select Korean in first window" }
            else if case .failure(let error) = inspection.raise(list[1]) { failure = "raise second iTerm2 window: \(error)" }
            else if !(await waitUntil({ self.automaticResultCount > countBeforeMove && self.service.currentSourceID == english && self.focusMonitor.currentFocus?.windowID != firstToken })) {
                failure = "AX notification did not switch English on second window"
            } else if service.selectSource(id: korean.id) != 0 { failure = "manual Korean in second window" }
            else {
                try? await Task.sleep(for: .milliseconds(150))
                if service.currentSourceID != korean.id { failure = "manual Korean overridden in same window" }
            }
        }
        automatic.stop()
        var cleanupFailures: [String] = []
        if case .failure(let error) = await verification.restore(originalWindow) {
            cleanupFailures.append("restore original window: \(error)")
        }
        _ = originalApp.activate(options: [.activateIgnoringOtherApps])
        if !(await waitUntil({ NSWorkspace.shared.frontmostApplication?.processIdentifier == originalApp.processIdentifier })) {
            cleanupFailures.append("restore original foreground application")
        }
        if originalApp.processIdentifier == target.processIdentifier, !(await inspection.waitForFocus(originalWindow)) {
            cleanupFailures.append("original window changed during application restoration")
        }
        try? await Task.sleep(for: .milliseconds(100))
        if service.selectSource(id: originalSource) != 0 || service.currentSourceID != originalSource {
            cleanupFailures.append("restore original input source")
        }
        if !cleanupFailures.isEmpty { failSmoke(([failure].compactMap { $0 } + cleanupFailures).joined(separator: "; ")) }
        if let failure { failSmoke(failure) }
        print("PASS: real iTerm2 window movement, manual Korean maintained, original app and source restored")
    }

    private func verifyRealTabSwitch() async {
        guard AXIsProcessTrusted() else { skipSmoke("tab switching requires Autoeng Accessibility permission") }
        guard let originalSource = service.currentSourceID, let english = settings.englishSourceID,
              let target = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }),
              let originalApp = NSWorkspace.shared.frontmostApplication,
              let korean = service.availableSources().first(where: { $0.isKeyboard && $0.isEnabled && $0.isSelectable && $0.languages.contains("ko") }) else {
            failSmoke("running iTerm2 and input sources required for tab verification")
        }
        let inspection = AccessibilityWindowInspection(processID: target.processIdentifier)
        let window: AccessibilityWindow
        switch inspection.readFocusedWindow() {
        case .success(let value): window = value
        case .failure(let error): failSmoke("capture original iTerm2 window: \(error)")
        }
        let reader = AccessibilityTabReader()
        guard let original = TabSelectionReader(backend: reader).selection(in: window),
              let tabs = reader.tabs(of: original.group),
              let destination = tabs.first(where: { $0 != original.tab }) else {
            skipSmoke("requires a visible iTerm2 tab bar with two existing accessible tabs")
        }
        func selected() -> AccessibilityWindow? {
            TabSelectionReader(backend: AccessibilityTabReader()).selection(in: window)?.tab
        }
        func press(_ tab: AccessibilityWindow) -> Bool {
            // iTerm2 may finish selecting the tab before returning from its UI action.
            // Verification actions allow rendering time; production reads stay bounded.
            AXUIElementSetMessagingTimeout(tab.element, 1)
            let result = AXUIElementPerformAction(tab.element, kAXPressAction as CFString)
            if result != .success { print("DIAGNOSTIC: tab press status \(result.rawValue)") }
            return result == .success
        }
        save(AppSettings(englishSourceID: english, targetBundleIDs: ["com.googlecode.iterm2"]))
        automatic.start()
        _ = target.activate(options: [.activateIgnoringOtherApps])
        var failure: String?
        if !(await waitUntil({ NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier })) {
            failure = "activate iTerm2 for tab verification"
        } else if case .failure(let error) = await WindowSwitchVerification(backend: inspection).restore(window) {
            failure = "focus iTerm2 window: \(error)"
        } else if !(await waitUntil({ self.focusMonitor.currentFocus?.tabID != nil })) {
            failure = "read and subscribe to selected iTerm2 tab"
        } else {
            try? await Task.sleep(for: .milliseconds(150))
            let before = automaticResultCount
            if service.selectSource(id: korean.id) != 0 { failure = "select Korean before tab move" }
            else if !press(destination) { failure = "press destination tab" }
            else if !(await waitUntil({ selected() == destination && self.automaticResultCount > before && self.service.currentSourceID == english })) {
                failure = "tab notification did not switch English"
            } else if service.selectSource(id: korean.id) != 0 { failure = "manual Korean in destination tab" }
            else {
                focusMonitor.refreshPermissions() // A baseline refresh must preserve manual Korean.
                try? await Task.sleep(for: .milliseconds(150))
                if service.currentSourceID != korean.id { failure = "manual Korean overridden in same tab" }
                else {
                    togglePause()
                    let pressed = press(original.tab)
                    let reached = await waitUntil({ selected() == original.tab })
                    if !pressed || !reached {
                        failure = "move tab while paused (press=\(pressed), reached=\(reached))"
                    } else {
                        try? await Task.sleep(for: .milliseconds(150))
                        if service.currentSourceID != korean.id { failure = "paused tab move changed input source" }
                        else {
                            togglePause()
                            if !(await waitUntil({ self.service.currentSourceID == english })) {
                                failure = "resume in selected tab (\(lastMessage ?? "no switching result"))"
                            }
                        }
                    }
                }
            }
        }
        automatic.stop()
        var cleanup: [String] = []
        if case .failure(let error) = await WindowSwitchVerification(backend: inspection).restore(window) {
            cleanup.append("restore original window: \(error)")
        }
        let pressedOriginal = press(original.tab)
        let restoredTab = await waitUntil({ selected() == original.tab })
        if !pressedOriginal || !restoredTab { cleanup.append("restore original tab") }
        _ = originalApp.activate(options: [.activateIgnoringOtherApps])
        if !(await waitUntil({ NSWorkspace.shared.frontmostApplication?.processIdentifier == originalApp.processIdentifier })) {
            cleanup.append("restore original foreground app")
        }
        if originalApp.processIdentifier == target.processIdentifier,
           (!(await inspection.waitForFocus(window)) || selected() != original.tab) { cleanup.append("original tab/window changed during restoration") }
        try? await Task.sleep(for: .milliseconds(100))
        if service.selectSource(id: originalSource) != 0 || service.currentSourceID != originalSource { cleanup.append("restore original input source") }
        if !cleanup.isEmpty { failSmoke(([failure].compactMap { $0 } + cleanup).joined(separator: "; ")) }
        if let failure { failSmoke(failure) }
        print("PASS: real iTerm2 tab switching, manual Korean maintained, pause/resume, original tab/window/app/source restored")
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        repeat {
            if condition() { return true }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
        } while clock.now < deadline
        return condition()
    }

    private func skipSmoke(_ message: String) -> Never {
        automatic.stop()
        if let smokeSuite { defaults.removePersistentDomain(forName: smokeSuite) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        print("SKIP: \(message)")
        print("RESULT: SKIP (exit 77)")
        exit(77)
    }

    private func failSmoke(_ message: String) -> Never {
        automatic.stop()
        if let smokeSuite { defaults.removePersistentDomain(forName: smokeSuite) }
        fputs("FAIL: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
