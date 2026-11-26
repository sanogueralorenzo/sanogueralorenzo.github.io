import Foundation

enum BrowserContentPackagePreparation {
    static func prepare(_ archive: Data, version: String) throws -> Data {
        guard archive.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw CocoaError(.fileReadCorruptFile) }
        let files = FileManager.default
        let temporary = files.temporaryDirectory.appendingPathComponent("BrowserContent-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: temporary) }

        let source = temporary.appendingPathComponent("Upstream.zip")
        let directory = temporary.appendingPathComponent("Extension", isDirectory: true)
        let output = temporary.appendingPathComponent("Prepared.zip")
        try archive.write(to: source)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        try run("/usr/bin/tar", ["-x", "--no-same-owner", "--no-same-permissions", "-f", source.path, "-C", directory.path])
        try validateFiles(in: directory)
        try prepareManifests(in: directory, version: version)
        try BrowserContentExtensionPatches.apply(in: directory)
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", directory.path, output.path])
        guard let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            (1...BrowserContentPackages.maximumArchiveSize).contains(size)
        else { throw CocoaError(.fileReadCorruptFile) }
        return try Data(contentsOf: output)
    }

    private static func validateFiles(in directory: URL) throws {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var inspectionError: Error?
        guard let entries = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
                inspectionError = error
                return false
            })
        else { throw CocoaError(.fileReadCorruptFile) }
        var totalSize = 0
        for case let entry as URL in entries {
            let values = try entry.resourceValues(forKeys: keys)
            guard values.isSymbolicLink == false, values.isRegularFile == true || values.isDirectory == true
            else { throw CocoaError(.fileReadCorruptFile) }
            if values.isRegularFile == true {
                let limit = 128 * 1_024 * 1_024
                guard let size = values.fileSize, size >= 0, size <= limit - totalSize
                else { throw CocoaError(.fileReadCorruptFile) }
                totalSize += size
            }
        }
        if let inspectionError { throw inspectionError }
    }

    private static func prepareManifests(in directory: URL, version: String) throws {
        let url = directory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        guard var manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            manifest["version"] as? String == version,
            var permissions = manifest["permissions"] as? [String], !permissions.contains("nativeMessaging"),
            var background = manifest["background"] as? [String: Any],
            background["scripts"] as? [String] == ["/js/background.js"],
            var network = manifest["declarative_net_request"] as? [String: Any],
            var rules = network["rule_resources"] as? [[String: Any]],
            let spanish = rules.firstIndex(where: { $0["id"] as? String == "spa-0" })
        else { throw CocoaError(.fileReadCorruptFile) }

        permissions.append("nativeMessaging")
        manifest["permissions"] = permissions
        background["scripts"] = ["/js/browser-startup.js"]
        manifest["background"] = background
        rules[spanish]["enabled"] = true
        network["rule_resources"] = rules
        manifest["declarative_net_request"] = network
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        try JSONSerialization.data(withJSONObject: manifest, options: options).write(to: url, options: .atomic)
        manifest["declarative_net_request"] = nil
        let cached = directory.appendingPathComponent("manifest-cached.json")
        try JSONSerialization.data(withJSONObject: manifest, options: options).write(to: cached, options: .atomic)
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
    }
}
