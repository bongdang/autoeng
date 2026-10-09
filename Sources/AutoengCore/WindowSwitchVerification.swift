public enum WindowDiagnosticError: Error, Equatable {
    case api(Int32)
    case invalidValue
    case missingFocusedWindow
    case focusMismatch
}

@MainActor
public protocol WindowVerificationBackend: AnyObject {
    associatedtype Window: Equatable
    func readWindows() -> Result<[Window], WindowDiagnosticError>
    func readFocusedWindow() -> Result<Window, WindowDiagnosticError>
    func raise(_ window: Window) -> Result<Void, WindowDiagnosticError>
    func waitForFocus(_ window: Window) async -> Bool
}

public enum WindowVerificationPreparation<Window> {
    case ready(windows: [Window], original: Window)
    case insufficientWindows
    case failed(WindowDiagnosticError)
}

@MainActor
public final class WindowSwitchVerification<Backend: WindowVerificationBackend> {
    private let backend: Backend
    public init(backend: Backend) { self.backend = backend }
    public func prepare() -> WindowVerificationPreparation<Backend.Window> {
        switch backend.readWindows() {
        case .failure(let error): return .failed(error)
        case .success(let windows):
            guard windows.count >= 2 else { return .insufficientWindows }
            switch backend.readFocusedWindow() {
            case .failure(let error): return .failed(error)
            case .success(let original): return .ready(windows: windows, original: original)
            }
        }
    }
    public func restore(_ window: Backend.Window) async -> Result<Void, WindowDiagnosticError> {
        switch backend.raise(window) {
        case .failure(let error): return .failure(error)
        case .success:
            guard await backend.waitForFocus(window) else { return .failure(.focusMismatch) }
            return .success(())
        }
    }
}
