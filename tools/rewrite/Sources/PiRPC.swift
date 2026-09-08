import Foundation

// One in-flight command per process. JSONL is split on LF only, so Unicode text
// separators remain intact. No source, output, or raw provider errors are logged.
@MainActor
final class PiRPC {
    private let process = Process()
    private let input = Pipe()
    private var buffer = Data()
    private var response: CheckedContinuation<Data, Error>?
    private var commandID = ""
    private var command = ""
    private var accepted = false
    private var completed = false
    private var events = Data()
    private var receivedBytes = 0
    private var deadline: Task<Void, Never>?
    var isRunning: Bool { process.isRunning }
    var processIdentifier: Int32 { process.processIdentifier }

    init(executable: URL, arguments: [String], environment: [String: String], directory: URL) throws {
        let output = Pipe(), errors = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.environment = environment; process.currentDirectoryURL = directory
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop(RewriteError.message("Pi stopped. Try the rewrite again.")) }
        }
        do { try process.run() }
        catch { throw RewriteError.message("Could not start Pi. Install Pi, then try again.") }
        let handle = output.fileHandleForReading
        DispatchQueue.global().async { [weak self] in
            defer { try? handle.close() }
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                DispatchQueue.main.async { [weak self] in self?.receive(data) }
            }
        }
        let errorHandle = errors.fileHandleForReading
        DispatchQueue.global().async {
            defer { try? errorHandle.close() }
            while !errorHandle.availableData.isEmpty { }
        }
    }
    deinit {
        process.terminationHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        deadline?.cancel()
    }
    func stop(_ error: Error = CancellationError()) {
        deadline?.cancel(); deadline = nil
        let pending = response; response = nil
        events.removeAll(); buffer.removeAll()
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            let pid = process.processIdentifier, group = getpgid(process.processIdentifier) == process.processIdentifier
            if group { kill(-pid, SIGTERM) } else { process.terminate() }
            let child = process
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if child.isRunning { kill(group ? -pid : pid, SIGKILL) }
            }
        }
        pending?.resume(throwing: error)
    }
    func send(_ command: String, message: String? = nil, timeout: Double = 90) async throws -> Data {
        try Task.checkCancellation()
        guard response == nil, isRunning else { throw RewriteError.message("Pi is not ready. Try the rewrite again.") }
        let id = UUID().uuidString
        var payload: [String: Any] = ["id": id, "type": command]
        if let message { payload["message"] = message }
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(10)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                response = continuation; commandID = id; self.command = command
                accepted = false; completed = false; events.removeAll(); receivedBytes = 0
                let handle = input.fileHandleForWriting, encoded = data
                DispatchQueue.global().async { [weak self] in
                    do { try handle.write(contentsOf: encoded) }
                    catch {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.commandID == id else { return }
                            self.stop(RewriteError.message("Could not send the rewrite to Pi. Try again."))
                        }
                    }
                }
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) } catch { return }
                    guard let self, self.commandID == id, self.response != nil else { return }
                    self.stop(RewriteError.message("Pi timed out. Try a shorter selection."))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.commandID == id else { return }
                self.stop()
            }
        }
    }
    func resetSession() async throws {
        _ = try await send("new_session", timeout: 15)
        let state = try await send("get_state", timeout: 15)
        guard let json = try JSONSerialization.jsonObject(with: state) as? [String: Any],
              let data = json["data"] as? [String: Any], data["messageCount"] as? Int == 0,
              data["pendingMessageCount"] as? Int == 0, data["isStreaming"] as? Bool == false else {
            throw RewriteError.message("Pi could not clear the previous rewrite. Try again.")
        }
    }
    private func finish(_ data: Data) {
        deadline?.cancel(); deadline = nil
        let pending = response; response = nil; events.removeAll()
        pending?.resume(returning: data)
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        receivedBytes += data.count
        guard buffer.count <= 2_000_000, receivedBytes <= 2_000_000 else {
            stop(RewriteError.message("Pi returned too much output. Try a smaller selection.")); return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = event["type"] as? String else {
                stop(RewriteError.message("Pi returned an invalid response. Update Pi and try again.")); return
            }
            guard response != nil else { continue }
            if type == "response" {
                guard event["id"] as? String == commandID else { continue }
                guard event["command"] as? String == command, event["success"] as? Bool == true,
                      (event["data"] as? [String: Any])?["cancelled"] as? Bool != true else {
                    stop(RewriteError.message("Pi could not complete the rewrite request. Check your model and sign-in.")); return
                }
                if command == "new_session", (event["data"] as? [String: Any])?["cancelled"] as? Bool != false {
                    stop(RewriteError.message("Pi could not clear the previous rewrite. Try again.")); return
                }
                if command != "prompt" { finish(line); continue }
                accepted = true
            } else if command == "prompt" {
                if type.hasPrefix("tool_execution") || type == "error" {
                    stop(RewriteError.message("Pi returned an unexpected action. The rewrite was discarded.")); return
                }
                if type == "message_end" || type == "agent_end" { events.append(line); events.append(10) }
                if type == "agent_end" { completed = true }
            }
            if command == "prompt", accepted, completed { finish(events) }
        }
    }
}
