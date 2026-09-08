import Foundation

@MainActor
enum ProcessTests {
    static let directory = URL(fileURLWithPath: "/private/tmp")
    static func io() async throws {
        let source = "Quotes: \"'\nUnicode: 🦊\nLiteral shell text: $(id)"
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], environment: CLIDiscovery.environment, directory: directory, input: source, timeout: 2)
        try expect(result.status == 0 && String(decoding: result.stdout, as: UTF8.self) == source, "Input did not round-trip literally")
        let failed = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo diagnostic >&2; exit 7"], environment: CLIDiscovery.environment, directory: directory, timeout: 2)
        try expect(failed.status == 7 && failed.stdout.isEmpty, "Exit status or stderr isolation lost")
    }

    static func failures() async throws {
        try await expectFailure(messageContains("timed out")) {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: CLIDiscovery.environment, directory: directory, timeout: 0.1)
        }
        let cancelled = Task {
            try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: CLIDiscovery.environment, directory: directory, timeout: 2)
        }
        cancelled.cancel()
        try await expectFailure({ $0 is CancellationError }) { _ = try await cancelled.value }
        try await expectFailure(messageContains("too much output")) {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/head"), arguments: ["-c", "2100000", "/dev/zero"], environment: CLIDiscovery.environment, directory: directory, timeout: 2)
        }
    }
}
