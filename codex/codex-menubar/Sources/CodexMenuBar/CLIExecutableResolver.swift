import Foundation

enum CLIExecutableResolver {
    static func resolve(commandName: String) -> String? {
        let fileManager = FileManager.default
        for prefix in fixedBinPrefixes {
            let path = URL(fileURLWithPath: prefix)
                .appendingPathComponent(commandName)
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func unresolvedMessage(commandName: String) -> String {
        "Could not resolve executable for \(commandName). Checked fixed install locations: \(fixedBinPrefixes.joined(separator: ", "))."
    }

    private static let fixedBinPrefixes = [
        "/opt/homebrew/bin",
        "/usr/local/bin"
    ]
}
