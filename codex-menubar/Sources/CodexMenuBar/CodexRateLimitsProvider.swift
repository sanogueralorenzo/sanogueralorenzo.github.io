import Foundation

struct CodexRateLimitsSnapshot {
    let entries: [String]
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
            entries: ["Unavailable: \(reason)"]
        )
    }

    private func buildSnapshot(from result: RateLimitsResult) -> CodexRateLimitsSnapshot {
        let primaryLimit = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
        let primaryLine = compactLine(label: primaryLabel(windowDurationMins: primaryLimit.primary?.windowDurationMins),
                                      window: primaryLimit.primary,
                                      isWeekly: false)
        let weeklyLine = compactLine(label: "Weekly",
                                     window: primaryLimit.secondary,
                                     isWeekly: true)

        return CodexRateLimitsSnapshot(entries: [primaryLine, weeklyLine])
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

    private func compactLine(label: String, window: RateLimitWindow?, isWeekly: Bool) -> String {
        let percentText = window?.usedPercent.map { "\($0)%" } ?? "--"
        let resetText = formattedResetText(unixTimestamp: window?.resetsAt, isWeekly: isWeekly)
        return "\(label) \(percentText) \(resetText)"
    }

    private func primaryLabel(windowDurationMins: Int?) -> String {
        guard let minutes = windowDurationMins, minutes > 0 else {
            return "5h"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }

    private func formattedResetText(unixTimestamp: Int?, isWeekly: Bool) -> String {
        guard let unixTimestamp else {
            return "--"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(unixTimestamp))
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = isWeekly ? "MMM d" : "h:mma"
        return formatter.string(from: date)
    }
}
