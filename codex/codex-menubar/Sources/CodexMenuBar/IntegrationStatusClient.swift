import AppKit
import Foundation

struct IntegrationStatus: Sendable {
  enum State: Sendable {
    case checking
    case ready(summary: String, detail: String?)
    case actionNeeded(summary: String, detail: String)
    case missing(summary: String, detail: String)
    case error(summary: String, detail: String)
  }

  let toolName: String
  let state: State
}

enum IntegrationStatusClient {
  static func loadAll() -> [IntegrationStatus] {
    [githubStatus(), acliStatus()]
  }

  private static func githubStatus() -> IntegrationStatus {
    guard let executablePath = CLIExecutableResolver.resolve(commandName: "gh") else {
      return IntegrationStatus(
        toolName: "gh",
        state: .missing(
          summary: "Missing",
          detail: "Install with `brew install gh`."
        )
      )
    }

    let result = run(executablePath: executablePath, arguments: ["auth", "status"])
    if result.exitCode == 0 {
      let combined = combinedOutput(from: result)
      let detail = githubAccountDetail(from: combined)
      return IntegrationStatus(
        toolName: "gh",
        state: .ready(summary: "Connected", detail: detail)
      )
    }

    let combined = [result.stdout, result.stderr]
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if combined.localizedCaseInsensitiveContains("gh auth login")
      || combined.localizedCaseInsensitiveContains("not logged")
    {
      return IntegrationStatus(
        toolName: "gh",
        state: .actionNeeded(
          summary: "Login required",
          detail: "Run `gh auth login`."
        )
      )
    }

    return IntegrationStatus(
      toolName: "gh",
      state: .error(
        summary: "Error",
        detail: combined.isEmpty ? "Unable to determine GitHub CLI status." : combined
      )
    )
  }

  private static func acliStatus() -> IntegrationStatus {
    guard let executablePath = CLIExecutableResolver.resolve(commandName: "acli") else {
      return IntegrationStatus(
        toolName: "acli",
        state: .missing(
          summary: "Missing",
          detail: "Install with `brew install acli`."
        )
      )
    }

    let result = run(
      executablePath: executablePath, arguments: ["jira", "project", "list", "--limit", "1"])
    if result.exitCode == 0 {
      let authStatus = run(executablePath: executablePath, arguments: ["jira", "auth", "status"])
      let detail = jiraAccountDetail(from: combinedOutput(from: authStatus)) ?? "Jira: Connected"
      return IntegrationStatus(
        toolName: "acli",
        state: .ready(
          summary: "Connected",
          detail: detail
        )
      )
    }

    let combined = combinedOutput(from: result)
    if combined.localizedCaseInsensitiveContains("acli auth login")
      || combined.localizedCaseInsensitiveContains("unauthorized")
    {
      return IntegrationStatus(
        toolName: "acli",
        state: .actionNeeded(
          summary: "Login required",
          detail: "Run `acli auth login`."
        )
      )
    }

    return IntegrationStatus(
      toolName: "acli",
      state: .error(
        summary: "Error",
        detail: combined.isEmpty ? "Unable to determine Atlassian CLI status." : combined
      )
    )
  }

  private static func combinedOutput(from result: ProcessResult) -> String {
    [result.stdout, result.stderr]
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func run(executablePath: String, arguments: [String]) -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.environment = CLIProcessEnvironment.make()

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return ProcessResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
    }

    return ProcessResult(
      exitCode: process.terminationStatus,
      stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        ?? "",
      stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
  }

  private static func githubAccountDetail(from text: String) -> String? {
    for line in text.split(separator: "\n").map(String.init) {
      if let range = line.range(of: "Logged in to github.com account ") {
        let account = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let normalized = account.split(separator: " ").first.map(String.init) ?? account
        return "GitHub: \(normalized)"
      }
    }
    return nil
  }

  private static func jiraAccountDetail(from text: String) -> String? {
    for line in text.split(separator: "\n").map(String.init) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if let value = trimmed.split(separator: ":", maxSplits: 1).dropFirst().first,
        trimmed.hasPrefix("Email:")
      {
        return "Jira: \(value.trimmingCharacters(in: .whitespaces))"
      }
    }
    return nil
  }
}

private struct ProcessResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}
