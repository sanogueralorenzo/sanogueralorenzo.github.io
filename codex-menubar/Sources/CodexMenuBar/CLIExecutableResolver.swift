import Foundation

enum CLIExecutableResolver {
    static func resolve(commandName: String) -> String? {
        guard let prefix = npmPrefix() else {
            return nil
        }

        return URL(fileURLWithPath: prefix)
            .appendingPathComponent("bin")
            .appendingPathComponent(commandName)
            .path
    }

    static func unresolvedMessage(commandName: String) -> String {
        "Could not resolve npm global bin for \(commandName). Ensure npm is installed and `npm config get prefix` works."
    }

    private static func npmPrefix() -> String? {
        guard let prefix = runAndReadStdout(executable: "/usr/bin/env",
                                            arguments: ["npm", "config", "get", "prefix"]) else {
            return nil
        }

        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "undefined" || trimmed == "null" {
            return nil
        }

        return trimmed
    }

    private static func runAndReadStdout(executable: String,
                                         arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
