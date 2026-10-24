import Darwin
import Foundation

/// Newline-delimited messages over one file descriptor: the agent's standard
/// streams or the socket to Crest. Lines are read on a thread of their own and
/// handed out in order; writes go out whole, one at a time. A line longer than
/// `maximumLineLength` ends the channel.
final class AgentLineChannel: @unchecked Sendable {
    // MARK: - Static Variables

    static let maximumLineLength = 8 << 20

    // MARK: - Variables

    private let input: Int32
    private let output: Int32
    private let writing = NSLock()

    // MARK: - Initializers

    init(input: Int32, output: Int32) {
        self.input = input
        self.output = output
    }

    // MARK: - Actions - Reading

    /// The lines that arrive, until the other end closes or a line grows too
    /// long.
    func lines() -> AsyncStream<Data> {
        let input = input
        return AsyncStream { continuation in
            Thread.detachNewThread {
                var pending = Data()
                var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                while true {
                    let count = read(input, &buffer, buffer.count)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { break }
                    pending.append(contentsOf: buffer[0..<count])
                    while let newline = pending.firstIndex(of: 0x0A) {
                        let line = pending[pending.startIndex..<newline]
                        pending.removeSubrange(pending.startIndex...newline)
                        if !line.isEmpty { continuation.yield(Data(line)) }
                    }
                    if pending.count > Self.maximumLineLength { break }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Actions - Writing

    /// Writes `line` and a newline; false once the other end is gone.
    @discardableResult
    func send(_ line: Data) -> Bool {
        writing.lock()
        defer { writing.unlock() }
        var message = line
        message.append(0x0A)
        return message.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(output, bytes.baseAddress! + offset, bytes.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    func close() {
        Darwin.close(input)
        if output != input { Darwin.close(output) }
    }
}
