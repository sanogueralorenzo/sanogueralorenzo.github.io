import CryptoKit
import Foundation
import WebKit

@MainActor
final class BrowserContentExtension {
    enum Variant: Hashable {
        case bundled
        case cached
    }

    nonisolated static let packageHash: SHA256.Digest? = {
        guard let url = Bundle.main.url(forResource: "uBlockOriginLite", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return SHA256.hash(data: data)
    }()

    private let directory: URL
    private let archive = Bundle.main.url(forResource: "uBlockOriginLite", withExtension: "zip")
    private var extensions: [Variant: Task<WKWebExtension, Error>] = [:]
    private var cachedCopy: Task<URL, Error>?

    init(profile: URL) {
        directory = profile.appendingPathComponent("ContentBlocking/Extension", isDirectory: true)
    }

    func load(_ variant: Variant) async throws -> WKWebExtension {
        if let task = extensions[variant] { return try await task.value }
        let task = Task {
            let url: URL
            switch variant {
            case .bundled:
                guard let archive else { throw CocoaError(.fileNoSuchFile) }
                url = archive
            case .cached:
                url = try await prepareCachedCopy()
            }
            return try await WKWebExtension(resourceBaseURL: url)
        }
        extensions[variant] = task
        do {
            return try await task.value
        } catch {
            extensions[variant] = nil
            throw error
        }
    }

    func prepareCachedCopy() async throws -> URL {
        if let cachedCopy { return try await cachedCopy.value }
        guard let archive, let hash = Self.packageHash else { throw CocoaError(.fileNoSuchFile) }
        let version = hash.map { String(format: "%02x", $0) }.joined()
        let directory = directory
        let task = Task.detached(priority: .utility) {
            try Self.unpack(archive, into: directory, version: version)
        }
        cachedCopy = task
        do {
            return try await task.value
        } catch {
            cachedCopy = nil
            throw error
        }
    }

    private nonisolated static func unpack(_ archive: URL, into directory: URL, version: String) throws -> URL {
        let files = FileManager.default
        let destination = directory.appendingPathComponent(version, isDirectory: true)
        let manifestName = "manifest.json"
        if let data = try? Data(contentsOf: destination.appendingPathComponent(manifestName)),
            let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let background = manifest["background"] as? [String: Any],
            background["scripts"] as? [String] == ["/js/browser-startup.js"],
            manifest["declarative_net_request"] == nil,
            files.isReadableFile(atPath: destination.appendingPathComponent("js/browser-startup.js").path)
        {
            return destination
        }

        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = directory.appendingPathComponent(".unpacking-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: staging) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, staging.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }

        let manifest = staging.appendingPathComponent(manifestName)
        try files.removeItem(at: manifest)
        try files.moveItem(at: staging.appendingPathComponent("manifest-cached.json"), to: manifest)
        if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
        try files.moveItem(at: staging, to: destination)
        if let entries = try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent != version {
                let name = entry.lastPathComponent
                if name.hasPrefix(".unpacking-") || (name.count == 64 && name.allSatisfy(\.isHexDigit)) {
                    try? files.removeItem(at: entry)
                }
            }
        }
        return destination
    }
}
