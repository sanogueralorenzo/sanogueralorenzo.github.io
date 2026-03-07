#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

final class FileLock {
    private let fd: Int32

    init(lockFile: URL) throws {
        fd = open(lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        if fd == -1 {
            throw AuthManagerError.ioFailure("Failed to open lock file: \(lockFile.path)")
        }
        if flock(fd, LOCK_EX) != 0 {
            _ = close(fd)
            throw AuthManagerError.ioFailure("Failed to lock auth file: \(lockFile.path)")
        }
    }

    deinit {
        _ = flock(fd, LOCK_UN)
        _ = close(fd)
    }
}
