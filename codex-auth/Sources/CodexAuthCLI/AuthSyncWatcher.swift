import CodexAuthCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

struct AuthSyncWatcher {
    enum Status: Equatable {
        case stopped
        case running(pid: Int32)
    }

    enum Error: LocalizedError {
        case failedToStart(String)
        case failedToStop(String)

        var errorDescription: String? {
            switch self {
            case .failedToStart(let message):
                return "Failed to start watcher: \(message)"
            case .failedToStop(let message):
                return "Failed to stop watcher: \(message)"
            }
        }
    }

    private struct FileSnapshot: Equatable {
        let modificationTime: TimeInterval
        let size: Int64
        let inode: Int64
    }

    private let manager: ProfileManager
    private let authFilePath: String
    private let stateDirectory: URL
    private let pidFileURL: URL
    private let logFileURL: URL

    init(homeDirectory: URL) {
        self.manager = ProfileManager(homeDirectory: homeDirectory)
        self.authFilePath = manager.paths.codexAuthFile.path
        self.stateDirectory = manager.paths.managerDirectory
        self.pidFileURL = stateDirectory.appendingPathComponent("codex-auth-watch.pid")
        self.logFileURL = stateDirectory.appendingPathComponent("codex-auth-watch.log")
    }

    func status() -> Status {
        guard let pid = readPID(), isProcessRunning(pid) else {
            clearPIDFileIfPresent()
            return .stopped
        }
        return .running(pid: pid)
    }

    func startDaemon(executablePath: String, homeDirectory: URL) throws -> Int32 {
        if case .running(let pid) = status() {
            return pid
        }

        try ensureStateDirectory()

        let command = """
nohup '\(shellEscaped(executablePath))' --home '\(shellEscaped(homeDirectory.path))' watch run > '\(shellEscaped(logFileURL.path))' 2>&1 & echo $!
"""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw Error.failedToStart(output.isEmpty ? "shell command failed" : output)
        }
        guard let pid = Int32(output) else {
            throw Error.failedToStart(output.isEmpty ? "did not return process id" : output)
        }

        try Data("\(pid)".utf8).write(to: pidFileURL, options: .atomic)
        return pid
    }

    func stopDaemon() throws {
        guard let pid = readPID() else {
            return
        }

        if kill(pid, SIGTERM) != 0 {
            clearPIDFileIfPresent()
            throw Error.failedToStop("could not signal process \(pid)")
        }

        clearPIDFileIfPresent()
    }

    func runLoop() throws -> Never {
        var lastSnapshot = snapshot()

        while true {
            let newSnapshot = snapshot()
            if newSnapshot != lastSnapshot {
                lastSnapshot = newSnapshot
                _ = try? manager.syncActiveProfileWithCurrentAuth()
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func snapshot() -> FileSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: authFilePath) else {
            return nil
        }

        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? -1
        return FileSnapshot(modificationTime: mtime, size: size, inode: inode)
    }

    private func readPID() -> Int32? {
        guard let data = try? Data(contentsOf: pidFileURL),
              let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(raw) else {
            return nil
        }
        return pid
    }

    private func clearPIDFileIfPresent() {
        if FileManager.default.fileExists(atPath: pidFileURL.path) {
            try? FileManager.default.removeItem(at: pidFileURL)
        }
    }

    private func ensureStateDirectory() throws {
        if !FileManager.default.fileExists(atPath: stateDirectory.path) {
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        }
    }

    private func isProcessRunning(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func shellEscaped(_ raw: String) -> String {
        raw.replacingOccurrences(of: "'", with: "'\\''")
    }
}
