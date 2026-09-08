import Foundation

struct ProcessOutput { let status: Int32; let stdout: Data }

// Pipes are drained concurrently, including stderr, without logging or retaining stderr.
// Output is bounded so a broken CLI cannot exhaust memory or deadlock a full pipe.
private final class ProcessBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var overflow = false
    func drain(_ handle: FileHandle, retain: Bool) {
        defer { try? handle.close() }
        while let chunk = try? handle.read(upToCount: 8192), !chunk.isEmpty {
            if retain {
                lock.lock()
                if bytes.count + chunk.count <= 2_000_000 { bytes.append(chunk) } else { overflow = true }
                lock.unlock()
            }
        }
    }
    func result() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if overflow { throw RewriteError.message("The processor returned too much output. Try a smaller selection.") }
        return bytes
    }
}

@MainActor
final class ProcessRunner {
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    private var deadline: Task<Void, Never>?

    func cancel() { cancelled = true; stop() }
    private func stop() {
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        let ownsGroup = getpgid(pid) == pid
        if ownsGroup { kill(-pid, SIGTERM) } else { process.terminate() }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if ownsGroup { kill(-pid, SIGKILL) }
            else if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    func run(executable: URL, arguments: [String], environment: [String: String], directory: URL,
             input: String = "", timeout: Double = 90) async throws -> ProcessOutput {
        try Task.checkCancellation()
        let process = Process(), output = Pipe(), errors = Pipe(), stdin = Pipe()
        let bytes = ProcessBytes(), group = DispatchGroup()
        self.process = process
        process.executableURL = executable; process.arguments = arguments
        process.environment = environment; process.currentDirectoryURL = directory
        process.standardInput = stdin; process.standardOutput = output; process.standardError = errors
        defer { self.process = nil; deadline?.cancel(); deadline = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    group.notify(queue: .main) {
                        MainActor.assumeIsolated {
                            if self.cancelled { continuation.resume(throwing: CancellationError()) }
                            else if self.timedOut { continuation.resume(throwing: RewriteError.message("The processor timed out. Try a shorter selection.")) }
                            else {
                                do { continuation.resume(returning: ProcessOutput(status: process.terminationStatus, stdout: try bytes.result())) }
                                catch { continuation.resume(throwing: error) }
                            }
                        }
                    }
                }
                // Enter before launch: a very short-lived process may exit immediately.
                group.enter(); group.enter(); group.enter()
                do { try process.run() }
                catch {
                    process.terminationHandler = nil
                    group.leave(); group.leave(); group.leave()
                    continuation.resume(throwing: RewriteError.message("Could not launch the processor. Check its installation in Settings."))
                    return
                }
                DispatchQueue.global().async { bytes.drain(output.fileHandleForReading, retain: true); group.leave() }
                DispatchQueue.global().async { bytes.drain(errors.fileHandleForReading, retain: false); group.leave() }
                DispatchQueue.global().async {
                    try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                    try? stdin.fileHandleForWriting.close(); group.leave()
                }
                deadline = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) } catch { return }
                    if self.process === process && process.isRunning { self.timedOut = true; self.stop() }
                }
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
}
