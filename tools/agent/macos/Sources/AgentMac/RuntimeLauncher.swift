import Foundation

@MainActor
final class RuntimeLauncher {
    private var process: Process?

    func ensureRunning() async throws -> RuntimeClient {
        if let client = try? RuntimeClient.discover(), await client.health() { return client }
        try launch()
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if let client = try? RuntimeClient.discover(), await client.health() { return client }
        }
        throw RuntimeClientError.notRunning
    }

    private func launch() throws {
        let task = Process()
        guard let executable = ProcessInfo.processInfo.environment["AGENT_EXECUTABLE"]
                ?? ["/opt/homebrew/bin/agent", "/usr/local/bin/agent"].first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw RuntimeClientError.notRunning
        }
        task.executableURL = URL(filePath: executable)
        task.arguments = ["serve"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        process = task
    }
}
