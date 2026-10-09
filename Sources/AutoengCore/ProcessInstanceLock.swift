import Foundation
import Darwin

public enum InstanceLockResult: Equatable {
    case acquired
    case inUse
    case failed(Int32)
}

public final class ProcessInstanceLock {
    private let url: URL
    private var descriptor: Int32 = -1
    public init(url: URL) { self.url = url }
    public func acquire() -> InstanceLockResult {
        if descriptor >= 0 { return .acquired }
        var openError: Int32 = 0
        let candidate = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { openError = EINVAL; return -1 }
            let value = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
            if value < 0 { openError = errno } // Capture before Swift/Foundation cleanup can change errno.
            return value
        }
        guard candidate >= 0 else { return .failed(openError) }
        guard flock(candidate, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(candidate)
            return code == EWOULDBLOCK || code == EAGAIN ? .inUse : .failed(code)
        }
        descriptor = candidate
        return .acquired
    }
    public func release() {
        guard descriptor >= 0 else { return }
        close(descriptor)
        descriptor = -1
        // Keep the inode: unlinking it would let another process lock a different file.
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}
