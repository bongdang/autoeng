import AppKit
import ApplicationServices
import AutoengCore

@main
@MainActor
enum AppMain {
    static func main() {
        if CommandLine.arguments.contains("--diagnose-permission") {
            let trusted = AXIsProcessTrusted()
            print("Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
            print("Path: \(Bundle.main.bundlePath)")
            print("Executable: \(Bundle.main.executablePath ?? "unknown")")
            print("PID: \(ProcessInfo.processInfo.processIdentifier)")
            print("PERMISSION: \(trusted ? "TRUSTED" : "NOT_TRUSTED")")
            exit(trusted ? EXIT_SUCCESS : 77)
        }
        let smoke = CommandLine.arguments.contains("--smoke-test")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Autoeng", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            fputs("FAIL: cannot prepare Autoeng instance lock: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
        let lock = ProcessInstanceLock(url: support.appendingPathComponent("instance.lock"))
        switch lock.acquire() {
        case .acquired: break
        case .inUse:
            fputs("BLOCKED: another Autoeng instance is running; no input changes performed\n", stderr)
            exit(smoke ? EXIT_FAILURE : EXIT_SUCCESS)
        case .failed(let code):
            fputs("FAIL: cannot acquire Autoeng instance lock (\(code)); no input changes performed\n", stderr)
            exit(EXIT_FAILURE)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let controller = AppController(
            smokeTest: smoke,
            verifyInputSwitch: CommandLine.arguments.contains("--verify-input-switch"),
            verifyAppActivation: CommandLine.arguments.contains("--verify-app-activation"),
            verifyWindowSwitch: CommandLine.arguments.contains("--verify-window-switch"),
            verifyTabSwitch: CommandLine.arguments.contains("--verify-tab-switch")
        )
        application.delegate = controller
        withExtendedLifetime((controller, lock)) {
            application.run()
        }
    }
}
