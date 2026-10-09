@preconcurrency import ApplicationServices
import Foundation
import AutoengCore

@MainActor
final class AccessibilityWindowInspection: WindowVerificationBackend {
    private let application: AXUIElement
    init(processID: Int32) {
        application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.1)
    }

    func readWindows() -> Result<[AccessibilityWindow], WindowDiagnosticError> {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard result == .success else { return .failure(.api(result.rawValue)) }
        guard let elements = value as? [AXUIElement] else { return .failure(.invalidValue) }
        return .success(elements.map { AccessibilityWindow(element: $0) })
    }

    func readFocusedWindow() -> Result<AccessibilityWindow, WindowDiagnosticError> {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        if result == .noValue { return .failure(.missingFocusedWindow) }
        guard result == .success else { return .failure(.api(result.rawValue)) }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .failure(.invalidValue) }
        return .success(AccessibilityWindow(element: unsafeDowncast(value, to: AXUIElement.self)))
    }

    func raise(_ window: AccessibilityWindow) -> Result<Void, WindowDiagnosticError> {
        AXUIElementSetMessagingTimeout(window.element, 0.1)
        let result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        return result == .success ? .success(()) : .failure(.api(result.rawValue))
    }

    func waitForFocus(_ window: AccessibilityWindow) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        repeat {
            if case .success(let actual) = readFocusedWindow(), actual == window { return true }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
        } while clock.now < deadline
        return false
    }
}
