#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

final class SessionInvalidator {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func invalidateRunningCodexSessions() -> SessionInvalidationResult {
        requestCodexAppQuit()

        let currentPID = getpid()
        let entries = runningProcesses()
        let officialCliEntrypoints = resolveOfficialCodexCliEntrypoints()
        var targets: [Int32: SessionKind] = [:]

        for entry in entries {
            guard entry.pid != currentPID else {
                continue
            }
            guard let kind = classifyProcess(command: entry.command,
                                             officialCliEntrypoints: officialCliEntrypoints) else {
                continue
            }

            if let existing = targets[entry.pid], existing == .app {
                continue
            }
            targets[entry.pid] = kind
        }

        var terminatedAppPIDs: [Int32] = []
        var terminatedCliPIDs: [Int32] = []
        var failedPIDs: [Int32] = []

        for (pid, kind) in targets.sorted(by: { $0.key < $1.key }) {
            if terminateProcess(pid: pid) {
                switch kind {
                case .app:
                    terminatedAppPIDs.append(pid)
                case .cli:
                    terminatedCliPIDs.append(pid)
                }
            } else {
                failedPIDs.append(pid)
            }
        }

        return SessionInvalidationResult(terminatedAppPIDs: terminatedAppPIDs,
                                         terminatedCliPIDs: terminatedCliPIDs,
                                         failedPIDs: failedPIDs)
    }

    private func requestCodexAppQuit() {
#if os(macOS)
        _ = runCommand(executablePath: "/usr/bin/osascript",
                       arguments: ["-e", "tell application \"Codex\" to quit"])
#endif
    }

    private func runningProcesses() -> [(pid: Int32, command: String)] {
        guard let commandResult = runCommand(executablePath: "/bin/ps",
                                             arguments: ["-axo", "pid=,command="]),
              commandResult.terminationStatus == 0,
              let text = String(data: commandResult.stdout, encoding: .utf8) else {
            return []
        }

        var result: [(pid: Int32, command: String)] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let pid = Int32(parts[0]) else {
                continue
            }

            let command = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                continue
            }

            result.append((pid: pid, command: command))
        }
        return result
    }

    private func classifyProcess(command: String,
                                 officialCliEntrypoints: Set<String>) -> SessionKind? {
        if command.contains("/Codex.app/Contents/") {
            return .app
        }

        if command.contains("codex-auth") {
            return nil
        }

        let tokens = command.split(whereSeparator: \.isWhitespace)
        for token in tokens {
            let raw = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if raw.isEmpty {
                continue
            }

            if officialCliEntrypoints.contains(raw) {
                return .cli
            }

            if raw.contains("/node_modules/@openai/codex/") ||
                raw.contains("/node_modules/@openai/codex-") {
                return .cli
            }
        }

        if command.lowercased().contains("@openai/codex") {
            return .cli
        }

        return nil
    }

    private func resolveOfficialCodexCliEntrypoints() -> Set<String> {
        guard let commandResult = runCommand(executablePath: whichExecutablePath(),
                                             arguments: ["-a", "codex"]),
              commandResult.terminationStatus == 0,
              let text = String(data: commandResult.stdout, encoding: .utf8) else {
            return []
        }

        var result: Set<String> = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let path = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                continue
            }

            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            if resolved.contains("/@openai/codex/") || path.contains("/@openai/codex/") {
                result.insert(path)
                result.insert(resolved)
            }
        }

        return result
    }

    private func whichExecutablePath() -> String {
        let candidates = ["/usr/bin/which", "/bin/which"]
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/which"
    }

    private func runCommand(executablePath: String,
                            arguments: [String]) -> (terminationStatus: Int32, stdout: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        return (terminationStatus: process.terminationStatus,
                stdout: output.fileHandleForReading.readDataToEndOfFile())
    }

    private func terminateProcess(pid: Int32) -> Bool {
        if !sendSignal(SIGTERM, to: pid) {
            return false
        }
        if waitForExit(pid: pid, timeoutMicroseconds: 500_000) {
            return true
        }

        if !sendSignal(SIGKILL, to: pid) {
            return false
        }
        return waitForExit(pid: pid, timeoutMicroseconds: 500_000)
    }

    private func sendSignal(_ signal: Int32, to pid: Int32) -> Bool {
        if kill(pid, signal) == 0 {
            return true
        }
        return errno == ESRCH
    }

    private func waitForExit(pid: Int32, timeoutMicroseconds: useconds_t) -> Bool {
        let interval: useconds_t = 100_000
        var waited: useconds_t = 0

        while waited < timeoutMicroseconds {
            if !isProcessAlive(pid: pid) {
                return true
            }
            usleep(interval)
            waited += interval
        }

        return !isProcessAlive(pid: pid)
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private enum SessionKind {
        case app
        case cli
    }
}
