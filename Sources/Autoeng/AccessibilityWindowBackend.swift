@preconcurrency import ApplicationServices
import AppKit
import AutoengCore

struct AccessibilityWindow: Equatable {
    let element: AXUIElement
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
}

@MainActor
final class AccessibilityWindowBackend: WindowObservationBackend {
    var onWindowChange: ((Int32) -> Void)?
    var onWindowDestroyed: ((AccessibilityWindow, Int32) -> Void)?
    var isTrusted: Bool { AXIsProcessTrusted() }
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var observedPID: Int32?
    private var destructionWindows: [AccessibilityWindow] = []
    private var tabGroup: AccessibilityWindow?
    private var tabWindow: AccessibilityWindow?
    private var observesTabs = false
    private(set) var windowReadStatus: WindowObservationStatus = .available
    private(set) var requiresWindowReconciliation = false

    func beginObserving(processID: Int32) -> WindowObservationStatus {
        guard isTrusted else { return .permissionRequired }
        var created: AXObserver?
        let result = AXObserverCreate(processID, { observer, element, notification, context in
            guard let context else { return }
            let backend = Unmanaged<AccessibilityWindowBackend>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard let current = backend.observer, CFEqual(current, observer), let pid = backend.observedPID else { return }
                if notification as String == kAXUIElementDestroyedNotification as String {
                    // Destroyed elements may no longer support AXUIElementGetPid.
                    let window = AccessibilityWindow(element: element)
                    if backend.tabWindow == window { backend.clearTabObservation() }
                    backend.destructionWindows.removeAll { $0 == window }
                    backend.onWindowDestroyed?(window, pid)
                } else {
                    backend.onWindowChange?(pid)
                }
            }
        }, &created)
        guard result == .success, let created else { return .failed(result.rawValue) }
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let added = AXObserverAddNotification(created, app, kAXFocusedWindowChangedNotification as CFString,
                                              Unmanaged.passUnretained(self).toOpaque())
        guard added == .success else {
            if added == .notificationUnsupported || added == .notImplemented { return .unsupported }
            return isTrusted ? .failed(added.rawValue) : .permissionRequired
        }
        observer = created
        application = app
        observedPID = processID
        observesTabs = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier == "com.googlecode.iterm2"
        if observesTabs {
            // Focus changes let us rediscover a tab bar after a window/layout change.
            _ = AXObserverAddNotification(created, app, kAXFocusedUIElementChangedNotification as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
        }
        requiresWindowReconciliation = false
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        return .available
    }

    func endObserving(processID: Int32) {
        guard observedPID == processID else { return }
        if let observer {
            clearTabObservation()
            if let application {
                AXObserverRemoveNotification(observer, application, kAXFocusedWindowChangedNotification as CFString)
                if observesTabs {
                    AXObserverRemoveNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        application = nil
        observedPID = nil
        observesTabs = false
        destructionWindows.removeAll()
    }

    func focusedWindow(processID: Int32) -> AccessibilityWindow? {
        windowReadStatus = .available
        guard isTrusted else { windowReadStatus = .permissionRequired; return nil }
        guard observedPID == processID, let application else {
            windowReadStatus = .failed(AXError.invalidUIElement.rawValue); return nil
        }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        if result == .noValue { return nil }
        guard result == .success else { windowReadStatus = .failed(result.rawValue); return nil }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            windowReadStatus = .failed(AXError.failure.rawValue); return nil
        }
        let window = AccessibilityWindow(element: unsafeDowncast(value, to: AXUIElement.self))
        if let observer, !destructionWindows.contains(window), !requiresWindowReconciliation {
            AXUIElementSetMessagingTimeout(window.element, 0.1)
            let added = AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString,
                                                  Unmanaged.passUnretained(self).toOpaque())
            if added == .success || added == .notificationAlreadyRegistered { destructionWindows.append(window) }
            else { requiresWindowReconciliation = true }
        }
        return window
    }

    func existingWindows(processID: Int32) -> [AccessibilityWindow]? {
        guard observedPID == processID, let application else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard result == .success else { windowReadStatus = .failed(result.rawValue); return nil }
        guard let elements = value as? [AXUIElement] else {
            windowReadStatus = .failed(AXError.failure.rawValue); return nil
        }
        let live = elements.map { AccessibilityWindow(element: $0) }
        destructionWindows.removeAll { !live.contains($0) }
        return live
    }

    func selectedTab(processID: Int32, window: AccessibilityWindow) -> AccessibilityWindow? {
        guard observesTabs, isTrusted, observedPID == processID, let observer,
              let selection = TabSelectionReader(backend: AccessibilityTabReader()).selection(in: window) else {
            clearTabObservation()
            return nil
        }
        if tabGroup != selection.group {
            clearTabObservation()
            let result = AXObserverAddNotification(observer, selection.group.element,
                                                   kAXValueChangedNotification as CFString,
                                                   Unmanaged.passUnretained(self).toOpaque())
            guard result == .success || result == .notificationAlreadyRegistered else { return nil }
            tabGroup = selection.group
        }
        tabWindow = window
        return selection.tab
    }

    private func clearTabObservation() {
        if let observer, let tabGroup {
            AXObserverRemoveNotification(observer, tabGroup.element, kAXValueChangedNotification as CFString)
        }
        tabGroup = nil
        tabWindow = nil
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
