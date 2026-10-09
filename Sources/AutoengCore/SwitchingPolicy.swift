/// A snapshot of the actual foreground application and its focused window.
public struct FocusContext: Equatable, Sendable {
    public let bundleID: String
    public let processID: Int32
    public let windowID: Int?
    public let tabID: Int?

    public init(bundleID: String, processID: Int32, windowID: Int? = nil, tabID: Int? = nil) {
        self.bundleID = bundleID
        self.processID = processID
        self.windowID = windowID
        self.tabID = tabID
    }
}

/// Determines when to apply a rule, independently of macOS API calls.
public struct SwitchingPolicy {
    public var targetBundleIDs: Set<String>
    public var isPaused = false
    private var previousFocus: FocusContext?

    public init(targetBundleIDs: Set<String>) {
        self.targetBundleIDs = targetBundleIDs
    }

    public mutating func shouldSwitch(to context: FocusContext?) -> Bool {
        guard let context else {
            previousFocus = nil
            return false
        }

        let sameProcess = previousFocus?.processID == context.processID
            && previousFocus?.bundleID == context.bundleID
        let windowChanged: Bool
        if sameProcess, let oldWindow = previousFocus?.windowID, let newWindow = context.windowID {
            windowChanged = oldWindow != newWindow
        } else {
            windowChanged = false
        }
        let tabChanged = sameProcess && context.windowID != nil
            && previousFocus?.windowID == context.windowID
            && previousFocus?.tabID != nil && context.tabID != nil
            && previousFocus?.tabID != context.tabID

        // An observation gap invalidates the old window baseline. Recovery is not a move.
        previousFocus = context
        return !isPaused && targetBundleIDs.contains(context.bundleID)
            && (!sameProcess || windowChanged || tabChanged)
    }

    public mutating func synchronize(to context: FocusContext?) {
        previousFocus = context
    }

    public mutating func resume(at context: FocusContext?) -> Bool {
        isPaused = false
        previousFocus = nil
        return shouldSwitch(to: context)
    }

    public mutating func processTerminated(_ processID: Int32) {
        if previousFocus?.processID == processID {
            previousFocus = nil
        }
    }
}
