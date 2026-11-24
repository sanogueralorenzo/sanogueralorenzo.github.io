import Darwin
import Foundation

enum BrowserCLISocket {
    static let requestLimit = 1_024 * 1_024
    static let responseLimit = 32 * requestLimit

    static func path(in directory: URL) -> String {
        directory.appendingPathComponent("cli.sock").path
    }

    static func make() throws -> Int32 {
        let descriptor = try check(socket(AF_UNIX, SOCK_STREAM, 0))
        do {
            try configure(descriptor)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    static func configure(_ descriptor: Int32) throws {
        var enabled: Int32 = 1
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        try check(fcntl(descriptor, F_SETFD, FD_CLOEXEC))
        try check(setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))))
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            try check(setsockopt(descriptor, SOL_SOCKET, option, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))))
        }
    }

    static func requireSameUser(_ descriptor: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        try check(getpeereid(descriptor, &uid, &gid))
        guard uid == geteuid() else { throw POSIXError(.EACCES) }
    }

    static func withAddress(
        _ path: String, _ action: (UnsafePointer<sockaddr>, socklen_t) -> Int32
    ) throws {
        var address = sockaddr_un()
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        _ = try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try check(action($0, socklen_t(MemoryLayout<sockaddr_un>.size)))
            }
        }
    }

    static func read(_ descriptor: Int32, limit: Int) throws -> Data {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        while let chunk = try handle.read(upToCount: 16_384), !chunk.isEmpty {
            guard chunk.count <= limit - data.count else { throw POSIXError(.EMSGSIZE) }
            data.append(chunk)
        }
        return data
    }

    static func write(_ data: Data, to descriptor: Int32) throws {
        try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).write(contentsOf: data)
    }

    @discardableResult
    static func check(_ result: Int32) throws -> Int32 {
        guard result >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return result
    }
}

@MainActor
final class BrowserCLIServer {
    private let path: String
    private let source: DispatchSourceRead

    init(directory: URL, execute: @escaping @MainActor @Sendable ([String]) -> BrowserCLIResponse) throws {
        let path = BrowserCLISocket.path(in: directory)
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard existing.st_mode & S_IFMT == S_IFSOCK, existing.st_uid == geteuid() else { throw POSIXError(.EEXIST) }
            try BrowserCLISocket.check(unlink(path))
        } else if errno != ENOENT {
            try BrowserCLISocket.check(-1)
        }

        let listener = try BrowserCLISocket.make()
        do {
            try BrowserCLISocket.withAddress(path) { bind(listener, $0, $1) }
        } catch {
            close(listener)
            throw error
        }
        do {
            try BrowserCLISocket.check(chmod(path, 0o600))
            try BrowserCLISocket.check(fcntl(listener, F_SETFL, O_NONBLOCK))
            try BrowserCLISocket.check(listen(listener, 8))
        } catch {
            close(listener)
            unlink(path)
            throw error
        }

        let queue = DispatchQueue.global(qos: .userInitiated)
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler { @Sendable in
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            queue.async { @Sendable in
                do {
                    try BrowserCLISocket.check(fcntl(client, F_SETFL, 0))
                    try BrowserCLISocket.configure(client)
                    try BrowserCLISocket.requireSameUser(client)
                    let request = try BrowserCLISocket.read(client, limit: BrowserCLISocket.requestLimit)
                    let arguments = try JSONDecoder().decode([String].self, from: request)
                    Task { @MainActor in
                        let response = execute(arguments)
                        queue.async { @Sendable in
                            defer { close(client) }
                            if let data = try? JSONEncoder().encode(response) {
                                try? BrowserCLISocket.write(data, to: client)
                            }
                        }
                    }
                } catch {
                    close(client)
                }
            }
        }
        source.setCancelHandler { @Sendable in close(listener) }
        self.path = path
        self.source = source
        source.resume()
    }

    func stop() {
        source.cancel()
        unlink(path)
    }
}
