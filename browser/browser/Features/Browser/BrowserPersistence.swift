import CryptoKit
import Darwin
import Foundation

/// Normal quit waits for the session checkpoint.
final class BrowserPersistence: Sendable {
    struct Envelope: Codable {
        let checksum: String
        let payload: Data
    }
    private struct SessionFormat: Decodable {
        let format: Int
    }
    let directory: URL
    private let lockDescriptor: Int32
    private var file: URL { directory.appendingPathComponent("session.json") }
    private var pending: URL { directory.appendingPathComponent(".session-pending") }
    private let writes = DispatchQueue(label: "com.itsbrowser.session-checkpoint", qos: .utility)

    init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        if let review = ProcessInfo.processInfo.environment["BROWSER_REVIEW_DATA_DIRECTORY"] {
            directory = URL(fileURLWithPath: review, isDirectory: true)
        } else {
            directory = support.appendingPathComponent("Browser/SwiftSession", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        lockDescriptor = Darwin.open(directory.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
            throw CocoaError(.fileLocking)
        }
        _ = unlink(pending.path)
    }

    deinit {
        flock(lockDescriptor, LOCK_UN)
        Darwin.close(lockDescriptor)
    }

    func load() throws -> BrowserSession {
        var info = stat()
        if lstat(file.path, &info) != 0 {
            let error = errno
            if error == ENOENT { return BrowserSession() }
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw CocoaError(.fileReadUnknown) }
        guard info.st_size <= 350 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: file)
        do {
            return try decodeSession(data)
        } catch is DecodingError {
            return BrowserSession()
        } catch let error as CocoaError where error.code == .fileReadCorruptFile {
            return BrowserSession()
        }
    }

    func save(_ value: BrowserSession) throws {
        try writes.sync { try write(value) }
    }

    func save(_ value: BrowserSession, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        writes.async { completion(Result { try self.write(value) }) }
    }

    private func write(_ value: BrowserSession) throws {
        let state = value.persistent()
        try state.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let payload = try encoder.encode(state)
        guard payload.count <= 256 * 1_024 * 1_024 else { throw CocoaError(.fileWriteOutOfSpace) }
        let envelope = Envelope(
            checksum: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(), payload: payload)
        try durableReplace(encoder.encode(envelope))
    }

    private func decodeSession(_ data: Data) throws -> BrowserSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard SHA256.hash(data: envelope.payload).map({ String(format: "%02x", $0) }).joined() == envelope.checksum
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let session: BrowserSession
        do {
            session = try decoder.decode(BrowserSession.self, from: envelope.payload)
        } catch let error as DecodingError {
            if let header = try? decoder.decode(SessionFormat.self, from: envelope.payload),
                header.format != BrowserSession.currentFormat
            {
                throw CocoaError(.fileReadUnknown)
            }
            throw error
        }
        try session.validate()
        return session
    }

    private func durableReplace(_ data: Data) throws {
        let temporary = pending
        let descriptor = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer {
            Darwin.close(descriptor)
            try? FileManager.default.removeItem(at: temporary)
        }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw POSIXError(.EIO) }
        // F_FULLFSYNC also flushes the drive cache.
        if fcntl(descriptor, F_FULLFSYNC) != 0, errno != ENOTSUP, errno != EINVAL { throw POSIXError(.EIO) }
        guard Darwin.rename(temporary.path, file.path) == 0 else { throw POSIXError(.EIO) }
        let parent = Darwin.open(directory.path, O_RDONLY)
        guard parent >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(parent) }
        if fsync(parent) != 0, errno != EINVAL, errno != ENOTSUP { throw POSIXError(.EIO) }
    }
}
