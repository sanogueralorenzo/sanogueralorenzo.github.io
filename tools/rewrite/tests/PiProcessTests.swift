import Foundation

@MainActor
enum PiProcessTests {
    static let directory = URL(fileURLWithPath: "/private/tmp")
    static func io() async throws {
        let output = try await PiProcess().run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["text 🦊"], environment: CLIDiscovery.environment, directory: directory, timeout: 2)
        try expect(output.status == 0 && String(decoding: output.stdout, as: UTF8.self) == "text 🦊\n", "Stdout was not captured exactly")
        let failed = try await PiProcess().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "head -c 2100000 /dev/zero >&2; exit 7"], environment: CLIDiscovery.environment, directory: directory, timeout: 2)
        try expect(failed.status == 7 && failed.stdout.isEmpty, "Exit status or stderr isolation lost")
    }

    static func failures() async throws {
        try await expectFailure(messageContains("timed out")) {
            _ = try await PiProcess().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: CLIDiscovery.environment, directory: directory, timeout: 0.1)
        }
        let cancelled = Task {
            try await PiProcess().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: CLIDiscovery.environment, directory: directory, timeout: 2)
        }
        cancelled.cancel()
        try await expectFailure({ $0 is CancellationError }) { _ = try await cancelled.value }
        try await expectFailure(messageContains("too much output")) {
            _ = try await PiProcess().run(executable: URL(fileURLWithPath: "/usr/bin/head"), arguments: ["-c", "2100000", "/dev/zero"], environment: CLIDiscovery.environment, directory: directory, timeout: 2)
        }
    }
}
