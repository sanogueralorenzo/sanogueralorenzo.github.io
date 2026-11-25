import Foundation
import WebKit

@MainActor
final class BrowserContentExtension {
    enum Variant: Hashable {
        case full
        case cached
    }

    private(set) var package: BrowserContentPackage?
    private let profile: URL
    private let directory: URL
    private var extensions: [Variant: Task<WKWebExtension, Error>] = [:]
    private var cachedCopy: Task<URL, Error>?
    private var defaultRules: Task<BrowserContentRuleCache.Entry?, Never>?

    init(profile: URL) {
        self.profile = profile
        directory = profile.appendingPathComponent("ContentBlocking/Extension", isDirectory: true)
    }

    func select(_ package: BrowserContentPackage) {
        self.package = package
        extensions.removeAll()
        cachedCopy?.cancel()
        cachedCopy = nil
        defaultRules?.cancel()
        defaultRules = nil
    }

    func prepareDefaultRules(for owner: BrowserSessionOwner) async -> BrowserContentRuleCache.Entry? {
        if defaultRules == nil,
            let package, let cache = BrowserContentRuleCache(profile: profile, packageHash: package.manifest.sha256) {
            defaultRules = Task { [weak owner] in
                if let rules = await cache.load() { return rules }
                guard !Task.isCancelled, let owner else { return nil }
                let seed = BrowserContentBlocking(spaceID: UUID(), owner: owner, dataStore: .nonPersistent(), isRuleSeed: true)
                return await seed.buildDefaultRules(in: cache)
            }
        }
        return await defaultRules?.value
    }

    func load(_ variant: Variant) async throws -> WKWebExtension {
        if let task = extensions[variant] { return try await task.value }
        guard let package else { throw CocoaError(.fileNoSuchFile) }
        let task = Task {
            let url: URL
            switch variant {
            case .full:
                url = package.archive
            case .cached:
                url = try await prepareCachedCopy()
            }
            let webExtension = try await WKWebExtension(resourceBaseURL: url)
            guard webExtension.version == package.manifest.version
            else { throw CocoaError(.fileReadCorruptFile) }
            return webExtension
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
        guard let package else { throw CocoaError(.fileNoSuchFile) }
        let directory = directory
        let task = Task.detached(priority: .utility) {
            try Self.unpack(package.archive, into: directory, version: package.manifest.sha256)
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
