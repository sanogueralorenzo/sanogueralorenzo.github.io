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
        if let executable = ProcessInfo.processInfo.environment["A1R_EXECUTABLE"] {
            task.executableURL = URL(filePath: executable)
            task.arguments = ["serve"]
        } else if let executable = ["/opt/homebrew/bin/a1r", "/usr/local/bin/a1r"].first(where: FileManager.default.isExecutableFile(atPath:)) {
            task.executableURL = URL(filePath: executable)
            task.arguments = ["serve"]
        } else if let root = findSourceRoot() {
            task.executableURL = URL(filePath: "/usr/bin/env")
            task.arguments = ["npm", "run", "serve", "--prefix", root.path]
        } else {
            throw RuntimeClientError.notRunning
        }
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        process = task
    }

    private func findSourceRoot() -> URL? {
        var current = URL(filePath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            let package = current.appending(path: "package.json")
            if let data = try? Data(contentsOf: package),
               String(decoding: data, as: UTF8.self).contains("\"name\": \"a1r\"") {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}
