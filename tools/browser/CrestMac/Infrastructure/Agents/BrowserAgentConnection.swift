import Darwin
import Foundation

/// One agent helper's connection to the agent socket: newline-delimited
/// messages in both directions. What arrives is split into lines on the
/// connection's own queue and handed to `receive`; `send` writes a line after
/// those sent before it. A line longer than `maximumLineLength` ends the
/// connection, since no request is that long, and so does a helper that
/// keeps more than `maximumOutstanding` lines unanswered, so no connection
/// holds more than a bounded amount of Crest's memory.
final class BrowserAgentConnection: @unchecked Sendable {
    // MARK: - Static Variables

    static let maximumLineLength = AgentLinkRequest.maximumBytes
    static let maximumOutstanding = 32

    // MARK: - Variables

    let peer: BrowserAgentPeer
    private let queue = DispatchQueue(label: "com.pauldavis.crest.agents.connection")
    private let channel: DispatchIO
    // Touched only on `queue`: what arrived after the last complete line, the
    // lines not yet answered, the writes not yet finished, and whether the
    // connection is ending or ended.
    private var pending = Data()
    private var outstanding = 0
    private var writing = 0
    private var closing = false
    private var ended = false

    // MARK: - Initializers

    init(descriptor: Int32, peer: BrowserAgentPeer) {
        self.peer = peer
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        channel = DispatchIO(type: .stream, fileDescriptor: descriptor, queue: queue) { _ in Darwin.close(descriptor) }
        channel.setLimit(lowWater: 1)
    }

    // MARK: - Actions - Messages

    /// Starts reading: each complete line goes to `receive`, and `ended` runs
    /// once when the tool hangs up, the connection fails or `close` ends it.
    func open(receive: @escaping @Sendable (Data) -> Void, ended: @escaping @Sendable () -> Void) {
        channel.read(offset: 0, length: Int.max, queue: queue) { [self] done, data, error in
            if let data, !data.isEmpty { take(data, receive: receive) }
            guard done || error != 0 else { return }
            finish()
            ended()
        }
    }

    /// Writes `line`, which answers one line that arrived, and a newline after
    /// everything sent before.
    func send(_ line: Data) {
        let message = line + [0x0A]
        queue.async { [self] in
            outstanding = max(0, outstanding - 1)
            guard !ended, !closing else { return }
            writing += 1
            message.withUnsafeBytes { bytes in
                channel.write(offset: 0, data: DispatchData(bytes: bytes), queue: queue) { [self] done, _, _ in
                    guard done else { return }
                    writing -= 1
                    if closing, writing == 0 { finish() }
                }
            }
        }
    }

    /// Ends the connection once everything sent before is written.
    func close() {
        queue.async { [self] in
            closing = true
            if writing == 0 { finish() }
        }
    }

    // MARK: - Mutators

    private func take(_ data: DispatchData, receive: (Data) -> Void) {
        guard !ended, !closing else { return }
        pending.append(contentsOf: data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            guard line.count <= Self.maximumLineLength else {
                finish()
                return
            }
            guard !line.isEmpty else { continue }
            outstanding += 1
            guard outstanding <= Self.maximumOutstanding else {
                finish()
                return
            }
            receive(Data(line))
        }
        if pending.count > Self.maximumLineLength { finish() }
    }

    /// Stops reading and writing and releases the socket. The read in
    /// progress then reports that it is done.
    private func finish() {
        guard !ended else { return }
        ended = true
        pending = Data()
        channel.close(flags: .stop)
    }
}
