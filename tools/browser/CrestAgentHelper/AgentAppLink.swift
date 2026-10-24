import Darwin
import Foundation

/// The helper's link to the Crest it ships inside: the socket, connected when
/// the agent first calls a tool and again after Crest goes and comes back.
/// Each call waits for its own answer.
actor AgentAppLink {
    // MARK: - Types

    /// Why a call reached no tool.
    enum Failure: Error {
        /// Crest is not running, or has agents turned off.
        case unreachable
        /// Crest refused the helper.
        case refused(AgentLinkRefusal)
        /// Crest went while the call waited.
        case closed
        /// The call is longer than Crest reads.
        case tooLarge

        /// What the agent's model reads instead of the tool's answer.
        var message: String {
            switch self {
            case .unreachable, .refused(.agentsOff):
                "Crest isn't running, or agents are turned off in Crest's Settings › Agents. Ask the person to open Crest and turn on agents."
            case .refused(.staleHelper):
                "Crest was updated since this connection started. Ask the person to restart Crest's MCP server in your agent."
            case .closed:
                "Crest closed the connection before the tool finished."
            case .tooLarge:
                "The call was too large to send to Crest. Send less at once, such as shorter text or a shorter script."
            }
        }
    }

    // MARK: - Variables

    private let path: String?
    private var channel: AgentLineChannel?
    private var nextID = 1
    private var waiting: [Int: CheckedContinuation<AgentToolResult, any Error>] = [:]
    private var attaching: CheckedContinuation<AgentJSON, any Error>?
    /// The tools Crest listed when the helper attached, when they differ from
    /// the helper's own.
    private(set) var tools: AgentJSON?

    // MARK: - Initializers

    init(path: String?) {
        self.path = path
    }

    // MARK: - Actions - Calls

    /// Calls tool `name` with `arguments` in Crest for the agent `client`, and
    /// answers what the tool answered. Throws a `Failure` when it reached no
    /// tool.
    func call(_ name: String, arguments: AgentJSON, client: AgentClientInfo?) async throws -> AgentToolResult {
        let id = nextID
        nextID += 1
        guard let line = try? JSONEncoder().encode(AgentLinkRequest.call(id: id, name: name, arguments: arguments))
        else { throw Failure.closed }
        guard line.count <= AgentLinkRequest.maximumBytes else { throw Failure.tooLarge }
        let channel = try await connected(client: client)
        return try await withCheckedThrowingContinuation { continuation in
            waiting[id] = continuation
            guard channel.send(line) else {
                waiting.removeValue(forKey: id)?.resume(throwing: Failure.closed)
                return
            }
        }
    }

    // MARK: - Actions - Responses

    /// Crest heard the agent and listed its tools as `tools`.
    func receiveAttached(_ tools: AgentJSON) {
        attaching?.resume(returning: tools)
        attaching = nil
    }

    /// Crest refused the helper for `reason`, so attaching and every call
    /// waiting fail.
    func receiveRefusal(_ reason: AgentLinkRefusal) {
        attaching?.resume(throwing: Failure.refused(reason))
        attaching = nil
        for continuation in waiting.values { continuation.resume(throwing: Failure.refused(reason)) }
        waiting = [:]
    }

    /// Crest answered call `id` with `result`.
    func receiveResult(_ result: AgentToolResult, for id: Int) {
        waiting.removeValue(forKey: id)?.resume(returning: result)
    }

    // MARK: - Mutators

    private func connected(client: AgentClientInfo?) async throws -> AgentLineChannel {
        if let channel { return channel }
        guard let path, let descriptor = Self.connect(path) else { throw Failure.unreachable }
        let channel = AgentLineChannel(input: descriptor, output: descriptor)
        self.channel = channel
        Task { await self.listen(to: channel) }
        guard
            let attach = try? JSONEncoder().encode(
                AgentLinkRequest.attach(version: AgentLinkRequest.version, client: client)),
            channel.send(attach)
        else {
            disconnect(channel)
            throw Failure.unreachable
        }
        let listed = try await withCheckedThrowingContinuation { attaching = $0 }
        tools = listed == AgentToolDefinition.catalog ? nil : listed
        return channel
    }

    private func listen(to channel: AgentLineChannel) async {
        for await line in channel.lines() {
            guard let response = try? JSONDecoder().decode(AgentLinkResponse.self, from: line) else { continue }
            response.deliver(to: self)
        }
        disconnect(channel)
    }

    private func disconnect(_ channel: AgentLineChannel) {
        guard self.channel === channel else { return }
        self.channel = nil
        channel.close()
        attaching?.resume(throwing: Failure.unreachable)
        attaching = nil
        for continuation in waiting.values { continuation.resume(throwing: Failure.closed) }
        waiting = [:]
    }

    /// A socket connected to `path`, or nil when nothing listens there.
    private static func connect(_ path: String) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.copyBytes(from: Array(path.utf8.prefix(bytes.count - 1)))
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }
}
