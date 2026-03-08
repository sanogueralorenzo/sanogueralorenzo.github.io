import Foundation

struct CodexRateLimitsSnapshot {
    let entries: [String]
    let sourceNote: String
}

final class CodexRateLimitsProvider: @unchecked Sendable {
    private struct JSONRPCResponse: Decodable {
        let id: Int?
        let result: RateLimitsResult?
        let error: JSONRPCError?
    }

    private struct JSONRPCError: Decodable {
        let message: String
    }

    private struct RateLimitsResult: Decodable {
        let rateLimits: RateLimitEntry
        let rateLimitsByLimitId: [String: RateLimitEntry]?
    }

    private struct RateLimitEntry: Decodable {
        let limitId: String?
        let limitName: String?
        let primary: RateLimitWindow?
        let secondary: RateLimitWindow?
        let credits: RateLimitCredits?
        let planType: String?
    }

    private struct RateLimitWindow: Decodable {
        let usedPercent: Int?
        let windowDurationMins: Int?
        let resetsAt: Int?
    }

    private struct RateLimitCredits: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let balance: String?
    }

    private let fileManager: FileManager
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func snapshot() -> CodexRateLimitsSnapshot {
        guard let codexExecutablePath = resolveCodexExecutablePath() else {
            return unavailableSnapshot(reason: "Codex CLI not found")
        }

        do {
            let response = try requestRateLimits(executablePath: codexExecutablePath)
            return buildSnapshot(from: response)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return unavailableSnapshot(reason: message)
        }
    }

    private func unavailableSnapshot(reason: String) -> CodexRateLimitsSnapshot {
        return CodexRateLimitsSnapshot(
            entries: ["Unavailable: \(reason)"],
            sourceNote: "Codex app-server"
        )
    }

    private func buildSnapshot(from result: RateLimitsResult) -> CodexRateLimitsSnapshot {
        var entries: [String] = []

        let allLimits = sortedLimits(from: result)

        if let planType = result.rateLimits.planType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !planType.isEmpty {
            entries.append("Plan: \(planType)")
        }

        if let credits = creditsLine(from: result.rateLimits) {
            entries.append(credits)
        }

        for limit in allLimits {
            entries.append(contentsOf: lines(for: limit))
        }

        if entries.isEmpty {
            entries = ["No rate limit data available"]
        }

        return CodexRateLimitsSnapshot(entries: entries,
                                       sourceNote: "Codex app-server")
    }

    private func resolveCodexExecutablePath() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let custom = env["CODEX_BIN"], fileManager.isExecutableFile(atPath: custom) {
            return custom
        }

        guard let npmGlobalCodexPath = CLIExecutableResolver.resolve(commandName: "codex") else {
            return nil
        }
        if fileManager.isExecutableFile(atPath: npmGlobalCodexPath) {
            return npmGlobalCodexPath
        }

        return nil
    }

    private func requestRateLimits(executablePath: String) throws -> RateLimitsResult {
        let decoder = JSONDecoder()
        let stdoutText = try runAppServerRateLimitRequest(executablePath: executablePath)
        let responseLines = stdoutText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in responseLines {
            guard let data = line.data(using: .utf8),
                  let response = try? decoder.decode(JSONRPCResponse.self, from: data) else {
                continue
            }

            if response.id == 2 {
                if let error = response.error {
                    throw NSError(
                        domain: "CodexRateLimitsProvider",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: error.message]
                    )
                }
                if let result = response.result {
                    return result
                }
            }
        }

        throw NSError(
            domain: "CodexRateLimitsProvider",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "account/rateLimits/read returned no result"]
        )
    }

    private func runAppServerRateLimitRequest(executablePath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server"]

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        let waitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            waitSemaphore.signal()
        }

        try process.run()
        let requestPayload = """
{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex_menubar","title":"Codex Menu Bar","version":"1.0.0"}}}
{"method":"initialized","params":{}}
{"id":2,"method":"account/rateLimits/read"}
"""
        if let payloadData = requestPayload.data(using: .utf8) {
            stdin.fileHandleForWriting.write(payloadData)
        }
        stdin.fileHandleForWriting.closeFile()

        let didTerminate = waitSemaphore.wait(timeout: .now() + 10) == .success
        if !didTerminate {
            process.terminate()
            throw NSError(
                domain: "CodexRateLimitsProvider",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for codex app-server response"]
            )
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return stdoutText
        }

        throw NSError(domain: "CodexRateLimitsProvider",
                      code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: stderrText])
    }

    private func sortedLimits(from result: RateLimitsResult) -> [RateLimitEntry] {
        let raw = result.rateLimitsByLimitId?.values.map { $0 } ?? [result.rateLimits]

        return raw.sorted { lhs, rhs in
            let lhsPriority = sortPriority(for: lhs)
            let rhsPriority = sortPriority(for: rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    private func sortPriority(for limit: RateLimitEntry) -> Int {
        if limit.limitId == "codex" {
            return 0
        }
        return 1
    }

    private func displayName(for limit: RateLimitEntry) -> String {
        if let name = limit.limitName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let id = limit.limitId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty {
            return id
        }
        return "default"
    }

    private func lines(for limit: RateLimitEntry) -> [String] {
        var lines: [String] = []
        let name = displayName(for: limit)

        if let primaryLine = windowLine(prefix: "\(name) (primary)", window: limit.primary) {
            lines.append(primaryLine)
        }
        if let secondaryLine = windowLine(prefix: "\(name) (secondary)", window: limit.secondary) {
            lines.append(secondaryLine)
        }

        if lines.isEmpty {
            lines.append("\(name): no active window")
        }

        return lines
    }

    private func windowLine(prefix: String, window: RateLimitWindow?) -> String? {
        guard let window else {
            return nil
        }

        let usageText: String
        if let usedPercent = window.usedPercent {
            usageText = "\(usedPercent)%"
        } else {
            usageText = "unknown usage"
        }

        let durationText: String
        if let minutes = window.windowDurationMins {
            durationText = "\(minutes)m"
        } else {
            durationText = "unknown window"
        }

        let resetText: String
        if let resetsAt = window.resetsAt {
            resetText = "resets \(relativeResetText(unixTimestamp: resetsAt))"
        } else {
            resetText = "reset unknown"
        }

        return "\(prefix): \(usageText) of \(durationText), \(resetText)"
    }

    private func creditsLine(from primary: RateLimitEntry) -> String? {
        guard let credits = primary.credits else {
            return nil
        }

        let availability = (credits.hasCredits == true) ? "available" : "none"
        if credits.unlimited == true {
            return "Credits: unlimited"
        }
        if let balance = credits.balance, !balance.isEmpty {
            return "Credits: \(availability), balance \(balance)"
        }
        return "Credits: \(availability)"
    }

    private func relativeResetText(unixTimestamp: Int) -> String {
        let now = Date()
        let resetDate = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))
        let delta = Int(resetDate.timeIntervalSince(now))
        if delta <= 0 {
            return "now"
        }
        if delta < 60 {
            return "in \(delta)s"
        }

        let minutes = delta / 60
        if minutes < 60 {
            return "in \(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            if remainingMinutes == 0 {
                return "in \(hours)h"
            }
            return "in \(hours)h \(remainingMinutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours == 0 {
            return "in \(days)d"
        }
        return "in \(days)d \(remainingHours)h"
    }
}
