import Foundation

enum ShellError: LocalizedError {
  case missingExecutable(String)
  case nonZeroExit(command: String, message: String)
  case timedOut(command: String)

  var errorDescription: String? {
    switch self {
    case .missingExecutable(let name):
      return "Missing executable: \(name)"
    case .nonZeroExit(let command, let message):
      return message.isEmpty ? "Command failed: \(command)" : "\(command): \(message)"
    case .timedOut(let command):
      return "Timed out: \(command)"
    }
  }
}

struct ShellResult: Sendable {
  let stdout: String
  let stderr: String
}

enum Shell {
  private static let fallbackSearchPaths = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
    "/Applications/Codex.app/Contents/Resources",
  ]

  private static func executableSearchPaths() -> [String] {
    let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
      .split(separator: ":")
      .map(String.init)
    var seen = Set<String>()
    return (envPaths + fallbackSearchPaths).filter { seen.insert($0).inserted }
  }

  static func resolve(_ executable: String) -> String? {
    if executable.contains("/") {
      return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
    }

    for directory in executableSearchPaths() {
      let candidate = URL(fileURLWithPath: directory)
        .appendingPathComponent(executable)
        .path
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  static func run(
    executable: String,
    arguments: [String],
    currentDirectory: URL? = nil,
    standardInput: String? = nil,
    timeout: TimeInterval = 60
  ) async throws -> ShellResult {
    guard let resolved = resolve(executable) else {
      throw ShellError.missingExecutable(executable)
    }

    return try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: resolved)
      process.arguments = arguments
      var environment = ProcessInfo.processInfo.environment
      environment["PATH"] = executableSearchPaths().joined(separator: ":")
      process.environment = environment
      if let currentDirectory {
        process.currentDirectoryURL = currentDirectory
      }

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe
      if let standardInput {
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        stdinPipe.fileHandleForWriting.write(Data(standardInput.utf8))
        try? stdinPipe.fileHandleForWriting.close()
      }

      let commandLine = ([executable] + arguments).joined(separator: " ")
      let timeoutTask = Task {
        try await Task.sleep(for: .seconds(timeout))
        if process.isRunning {
          process.terminate()
          continuation.resume(throwing: ShellError.timedOut(command: commandLine))
        }
      }

      process.terminationHandler = { process in
        timeoutTask.cancel()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0 {
          continuation.resume(returning: ShellResult(stdout: stdout, stderr: stderr))
        } else {
          continuation.resume(throwing: ShellError.nonZeroExit(command: commandLine, message: stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
      }

      do {
        try process.run()
      } catch {
        timeoutTask.cancel()
        continuation.resume(throwing: error)
      }
    }
  }
}
