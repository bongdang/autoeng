import Testing
@testable import AutoengCore

@MainActor
private final class VerificationBackend: WindowVerificationBackend {
    var list: Result<[Int], WindowDiagnosticError> = .success([1, 2])
    var focused: Result<Int, WindowDiagnosticError> = .success(1)
    var raiseResult: Result<Void, WindowDiagnosticError> = .success(())
    var confirmsFocus = true
    var focusedReads = 0
    var raised: [Int] = []
    var waited: [Int] = []
    func readWindows() -> Result<[Int], WindowDiagnosticError> { list }
    func readFocusedWindow() -> Result<Int, WindowDiagnosticError> { focusedReads += 1; return focused }
    func raise(_ window: Int) -> Result<Void, WindowDiagnosticError> { raised.append(window); return raiseResult }
    func waitForFocus(_ window: Int) async -> Bool { waited.append(window); return confirmsFocus }
}

@MainActor
struct WindowVerificationTests {
    @Test(arguments: [WindowDiagnosticError.api(-25204), .invalidValue])
    func readErrorsAreFailuresRatherThanInsufficientWindows(error: WindowDiagnosticError) {
        let backend = VerificationBackend(); backend.list = .failure(error)
        let subject = WindowSwitchVerification(backend: backend)
        if case .failed(let actual) = subject.prepare() { #expect(actual == error) }
        else { Issue.record("AX query error was hidden as a skip or success") }
        #expect(backend.raised.isEmpty)
    }

    @Test(arguments: [0, 1])
    func onlySuccessfulShortListIsInsufficient(count: Int) {
        let backend = VerificationBackend(); backend.list = .success(Array(0..<count))
        let subject = WindowSwitchVerification(backend: backend)
        if case .insufficientWindows = subject.prepare() {} else { Issue.record("Expected insufficient windows") }
        #expect(backend.focusedReads == 0)
        #expect(backend.raised.isEmpty)
    }

    @Test func capturesOriginalWindowBeforeAnyActions() {
        let backend = VerificationBackend(); backend.focused = .success(2)
        let subject = WindowSwitchVerification(backend: backend)
        if case .ready(let windows, let original) = subject.prepare() {
            #expect(windows == [1, 2]); #expect(original == 2)
        } else { Issue.record("Preparation did not capture the original window") }
        #expect(backend.raised.isEmpty)
    }

    @Test func missingOriginalWindowFailsBeforeAnyActions() {
        let backend = VerificationBackend(); backend.focused = .failure(.missingFocusedWindow)
        let subject = WindowSwitchVerification(backend: backend)
        if case .failed(let error) = subject.prepare() { #expect(error == .missingFocusedWindow) }
        else { Issue.record("Missing original window must not proceed") }
        #expect(backend.raised.isEmpty)
    }

    @Test func raiseFailureCannotReportSuccessfulRestoration() async {
        let backend = VerificationBackend(); backend.raiseResult = .failure(.api(-25204))
        let result = await WindowSwitchVerification(backend: backend).restore(1)
        if case .failure(let error) = result { #expect(error == .api(-25204)) }
        else { Issue.record("Failed raise was reported as successful restoration") }
        #expect(backend.waited.isEmpty)
    }

    @Test func successfulRaiseStillRequiresActualFocusConfirmation() async {
        let backend = VerificationBackend(); backend.confirmsFocus = false
        let result = await WindowSwitchVerification(backend: backend).restore(1)
        if case .failure(let error) = result { #expect(error == .focusMismatch) }
        else { Issue.record("Wrong focused window was reported as successful restoration") }
        #expect(backend.raised == [1]); #expect(backend.waited == [1])
    }

    @Test func successfulRestorationRaisesAndConfirmsOriginalWindow() async {
        let backend = VerificationBackend()
        let result = await WindowSwitchVerification(backend: backend).restore(2)
        if case .success = result {} else { Issue.record("Restoration unexpectedly failed") }
        #expect(backend.raised == [2]); #expect(backend.waited == [2])
    }
}
