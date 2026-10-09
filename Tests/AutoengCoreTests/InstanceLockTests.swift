import Foundation
import Darwin
import Testing
@testable import AutoengCore

// The subprocess probe briefly inherits other test descriptors before exec closes
// CLOEXEC handles. Serialize this suite so it cannot extend another case's lock.
@Suite(.serialized)
struct InstanceLockTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("autoeng-lock-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test func onlyOneOwnerAndReleaseAllowsRestart() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("instance.lock")
            let first = ProcessInstanceLock(url: url); let second = ProcessInstanceLock(url: url)
            #expect(first.acquire() == .acquired)
            #expect(first.acquire() == .acquired)
            #expect(second.acquire() == .inUse)
            second.release() // A losing contender must not release the owner's lock.
            #expect(second.acquire() == .inUse)
            first.release(); first.release()
            #expect(second.acquire() == .acquired)
            #expect(first.acquire() == .inUse)
            second.release()
            #expect(FileManager.default.fileExists(atPath: url.path)) // Never unlink a live lock inode.
        }
    }

    @Test func deallocationReleasesOwnership() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("instance.lock")
            var first: ProcessInstanceLock? = ProcessInstanceLock(url: url)
            #expect(first?.acquire() == .acquired)
            let second = ProcessInstanceLock(url: url)
            #expect(second.acquire() == .inUse)
            first = nil
            #expect(second.acquire() == .acquired)
        }
    }

    @Test func invalidPathFailsClosed() throws {
        try withDirectory { directory in
            let lock = ProcessInstanceLock(url: directory.appendingPathComponent("missing/instance.lock"))
            #expect(lock.acquire() == .failed(ENOENT))
        }
    }

    @Test func refusesSymlinkInsteadOfLockingAnotherFile() throws {
        try withDirectory { directory in
            let target = directory.appendingPathComponent("target")
            try Data().write(to: target)
            let link = directory.appendingPathComponent("instance.lock")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let lock = ProcessInstanceLock(url: link)
            #expect(lock.acquire() == .failed(ELOOP))
        }
    }

    @Test func otherProcessCannotAcquireUntilOwnerReleases() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("instance.lock")
            let owner = ProcessInstanceLock(url: url)
            #expect(owner.acquire() == .acquired)
            func probe() throws -> Int32 {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = ["-c", "import fcntl,sys\nf=open(sys.argv[1], 'a')\ntry:\n fcntl.flock(f, fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError:\n sys.exit(17)\n", url.path]
                try process.run(); process.waitUntilExit()
                return process.terminationStatus
            }
            let blocked = try probe()
            #expect(blocked == 17)
            owner.release()
            let available = try probe()
            #expect(available == 0)
        }
    }
}
