@preconcurrency import ApplicationServices
import AutoengCore

/// Reads structural roles and tab selection only. Never reads labels or text values.
@MainActor
final class AccessibilityTabReader: TabElementReading {
    private let deadline = ContinuousClock.now.advanced(by: .milliseconds(75))

    private func value(_ element: AccessibilityWindow, _ attribute: String) -> CFTypeRef? {
        guard ContinuousClock.now < deadline else { return nil }
        AXUIElementSetMessagingTimeout(element.element, 0.02)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element.element, attribute as CFString, &value) == .success,
              ContinuousClock.now < deadline else { return nil }
        return value
    }

    func role(of element: AccessibilityWindow) -> TabElementRole {
        guard let role = value(element, kAXRoleAttribute as String) as? String else { return .other }
        if role == kAXTabGroupRole as String { return .tabGroup }
        if role == kAXRadioButtonRole as String { return .tab }
        if [kAXWindowRole as String, kAXGroupRole as String, kAXSplitGroupRole as String].contains(role) { return .container }
        return .other
    }
    func children(of element: AccessibilityWindow) -> [AccessibilityWindow]? {
        elements(element, kAXChildrenAttribute as String)
    }
    func tabs(of group: AccessibilityWindow) -> [AccessibilityWindow]? {
        elements(group, kAXTabsAttribute as String)
    }
    private func elements(_ element: AccessibilityWindow, _ attribute: String) -> [AccessibilityWindow]? {
        guard let list = value(element, attribute) as? [AXUIElement] else { return nil }
        return list.map { AccessibilityWindow(element: $0) }
    }
    func isSelected(_ tab: AccessibilityWindow) -> Bool? {
        guard role(of: tab) == .tab, let number = value(tab, kAXValueAttribute as String) as? NSNumber else { return nil }
        return number.boolValue
    }
}
