import Darwin
import Foundation

/// The Unix domain socket agents reach this Crest through, by way of its
/// bundled `crest-browser` helper. The socket file lets its owner alone
/// connect, and any connection that is not from this Crest's own helper,
/// running as this user, is closed before anything is read from it.
/// Connections are accepted on a queue of the listener's own and handed to
/// `connected` there.
final class BrowserAgentListener: @unchecked Sendable {
    // MARK: - Types

    enum Failure: Error, Equatable {
        /// Another running Crest answers at the path.
        case inUse
        /// Something other than a socket is at the path.
        case occupied
        /// The system refused `operation` with `code`.
        case system(operation: Operation, code: Int32)
        /// This copy of Crest has no socket path, as when the account's home
        /// folder path is too long for one, or no helper to admit.
        case unavailable

        /// Why agents can't reach Crest while agents are on. Turning agents
        /// off and on again tries again.
        var message: LocalizedStringResource {
            switch self {
            case .inUse:
                "Another copy of Crest is already open to agents. Quit it, then turn agents off and on again."
            case .occupied, .system:
                "Crest couldn’t open itself to agents. Turn agents off and on again to try again."
            case .unavailable:
                "Agents can’t reach this copy of Crest."
            }
        }
    }

    /// What the listener asked the system for.
    enum Operation: Equatable {
        case makeDirectory
        case makeSocket
        case bind
    }

    /// A file by its device and inode, which tells the socket this listener
    /// bound from one a later launch bound at the same path.
    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    // MARK: - Variables

    let path: String
    private let helper: BrowserAgentHelperRequirement
    private let queue = DispatchQueue(label: "com.pauldavis.crest.agents.listener")
    private let connected: @Sendable (BrowserAgentConnection) -> Void
    /// What watches the listening socket while the listener runs, and what
    /// its cancellation signals once the socket is closed and removed. Its
    /// owner starts and stops the listener on one thread.
    private var source: DispatchSourceRead?
    private var closed: DispatchSemaphore?

    /// How long `stop` waits for the socket to close.
    private static let closeTimeout = DispatchTimeInterval.seconds(2)
    /// The most connections one wake-up accepts. The source wakes again for
    /// the rest, and a stop waits for one short batch at most.
    private static let acceptsPerWake = 16

    // MARK: - Initializers

    init(
        path: String, helper: BrowserAgentHelperRequirement,
        connected: @escaping @Sendable (BrowserAgentConnection) -> Void
    ) {
        self.path = path
        self.helper = helper
        self.connected = connected
    }

    deinit {
        source?.cancel()
    }

    // MARK: - Actions - Lifecycle

    /// Binds the socket and starts accepting connections. A socket a Crest
    /// that quit without removing it left behind is replaced; one a running
    /// Crest still answers is not.
    func start() throws(Failure) {
        guard source == nil else { return }
        let descriptor = try bind()
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        let path = path
        let identity = Self.identity(of: path)
        let closed = DispatchSemaphore(value: 0)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            acceptWaiting(on: descriptor) { source.isCancelled }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
            // Remove the socket only while it is still the one this listener bound.
            if let identity, Self.identity(of: path) == identity { unlink(path) }
            closed.signal()
        }
        self.source = source
        self.closed = closed
        source.resume()
    }

    /// Stops accepting connections and removes the socket before it returns,
    /// so the path can be bound again at once, and answers whether it did.
    /// It answers false only when the socket was still open after waiting
    /// `closeTimeout`. Connections already made stay open until their owner
    /// closes them.
    @discardableResult
    func stop() -> Bool {
        guard let source, let closed else { return true }
        self.source = nil
        self.closed = nil
        // The cancellation runs on the listener's own queue, never the
        // caller's, once a wake-up in progress returns.
        source.cancel()
        return closed.wait(timeout: .now() + Self.closeTimeout) == .success
    }

    // MARK: - Actions - Connections

    /// Accepts up to `acceptsPerWake` waiting connections, stopping early
    /// once `cancelled` says the listener is stopping.
    private func acceptWaiting(on descriptor: Int32, cancelled: () -> Bool) {
        for _ in 0..<Self.acceptsPerWake {
            guard !cancelled() else { return }
            let client = Darwin.accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            guard let peer = BrowserAgentPeer.verified(client, helper: helper) else {
                Darwin.close(client)
                continue
            }
            connected(BrowserAgentConnection(descriptor: client, peer: peer))
        }
    }

    // MARK: - Mutators

    /// A listening socket bound at `path`, readable and writable by its owner
    /// alone.
    private func bind() throws(Failure) -> Int32 {
        try clearStaleSocket()
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw .system(operation: .makeDirectory, code: Int32((error as NSError).code))
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .system(operation: .makeSocket, code: errno) }
        var address = Self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        // A connection made between binding and narrowing the mode is still
        // refused by the peer check.
        guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor, 16) == 0,
            fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0,
            fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0
        else {
            let code = errno
            Darwin.close(descriptor)
            throw .system(operation: .bind, code: code)
        }
        return descriptor
    }

    /// Removes a socket nothing answers at `path`, which a Crest that quit
    /// unexpectedly left behind.
    private func clearStaleSocket() throws(Failure) {
        var status = stat()
        guard lstat(path, &status) == 0 else { return }
        guard status.st_mode & S_IFMT == S_IFSOCK else { throw .occupied }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw .system(operation: .makeSocket, code: errno) }
        defer { Darwin.close(probe) }
        var address = Self.address(path)
        let answered = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard answered != 0 else { throw .inUse }
        unlink(path)
    }

    /// The address of a socket at `path`, which must fit one.
    private static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            let utf8 = Array(path.utf8.prefix(bytes.count - 1))
            bytes.copyBytes(from: utf8)
        }
        return address
    }

    /// The file at `path` by its device and inode, or nil when there is none.
    private static func identity(of path: String) -> FileIdentity? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return FileIdentity(device: status.st_dev, inode: status.st_ino)
    }
}
