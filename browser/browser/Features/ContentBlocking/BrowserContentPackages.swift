import CryptoKit
import Foundation

struct BrowserContentPackage: Sendable {
    struct Manifest: Codable, Sendable {
        let format: Int
        let version: String
        let sha256: String

        var isSupported: Bool {
            let components = version.split(separator: ".", omittingEmptySubsequences: false)
            return format == 1 && components.count == 3
                && components.allSatisfy { !$0.isEmpty && $0.count <= 8 && $0.utf8.allSatisfy { (48...57).contains($0) } }
                && Self.isDigest(sha256)
        }

        func supersedes(_ other: Self) -> Bool {
            sha256 != other.sha256 && version.compare(other.version, options: .numeric) != .orderedAscending
        }

        static func isDigest(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }

    let manifest: Manifest
    let archive: URL
}

actor BrowserContentPackages {
    static let maximumArchiveSize = 32 * 1_024 * 1_024

    private struct Selection: Codable {
        var active: BrowserContentPackage.Manifest?
        var pending: BrowserContentPackage.Manifest?
        var rejected: String?
    }

    private let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("Selection.json") }
    private let bundledArchive: URL?
    private let bundledManifest: URL?

    init(profile: URL, bundle: Bundle = .main) {
        directory = profile.appendingPathComponent("ContentBlocking/Packages", isDirectory: true)
        bundledArchive = bundle.url(forResource: "uBlockOriginLite", withExtension: "zip")
        bundledManifest = bundle.url(forResource: "uBlockOriginLite", withExtension: "json")
    }

    func builtIn() throws -> BrowserContentPackage {
        guard let bundledManifest, let bundledArchive else { throw CocoaError(.fileNoSuchFile) }
        let manifest = try JSONDecoder().decode(BrowserContentPackage.Manifest.self, from: Data(contentsOf: bundledManifest))
        guard let package = verified(manifest, archive: bundledArchive) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return package
    }

    func available() -> (active: BrowserContentPackage?, pending: BrowserContentPackage?) {
        let state = selection()
        let active = state.active.flatMap { manifest in
            verified(manifest, archive: archiveURL(for: manifest))
                ?? bundledArchive.flatMap { verified(manifest, archive: $0) }
        }
        let pending = state.pending.flatMap { verified($0, archive: archiveURL(for: $0)) }.flatMap { candidate -> BrowserContentPackage? in
            if let active, !candidate.manifest.supersedes(active.manifest) { return nil }
            return candidate
        }
        prune(state)
        return (active, pending)
    }

    func shouldDownload(_ manifest: BrowserContentPackage.Manifest, after active: BrowserContentPackage) -> Bool {
        let state = selection()
        return manifest.isSupported && manifest.sha256 != state.rejected
            && manifest.supersedes(active.manifest)
            && (state.pending?.sha256 != manifest.sha256 || verified(manifest, archive: archiveURL(for: manifest)) == nil)
    }

    func stage(_ manifest: BrowserContentPackage.Manifest, data: Data) throws -> BrowserContentPackage {
        guard manifest.isSupported, Self.matches(data, digest: manifest.sha256)
        else { throw CocoaError(.fileReadCorruptFile) }
        try createDirectory()
        let archive = archiveURL(for: manifest)
        try data.write(to: archive, options: .atomic)
        var state = selection()
        state.pending = manifest
        try save(state)
        return BrowserContentPackage(manifest: manifest, archive: archive)
    }

    func activate(_ package: BrowserContentPackage) throws {
        var state = selection()
        state.active = package.manifest
        state.pending = nil
        state.rejected = nil
        try save(state)
        prune(state)
    }

    func reject(_ package: BrowserContentPackage, retaining active: BrowserContentPackage?) throws {
        var state = selection()
        state.pending = nil
        state.rejected = active == nil ? nil : package.manifest.sha256
        try save(state)
        prune(state)
    }

    private func selection() -> Selection {
        guard let data = try? Data(contentsOf: stateURL),
            let state = try? JSONDecoder().decode(Selection.self, from: data)
        else { return Selection() }
        return state
    }

    private func createDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func save(_ state: Selection) throws {
        try createDirectory()
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    private func verified(_ manifest: BrowserContentPackage.Manifest, archive: URL) -> BrowserContentPackage? {
        guard manifest.isSupported, let values = try? archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
            values.isRegularFile == true, values.isSymbolicLink != true,
            let size = values.fileSize, (1...Self.maximumArchiveSize).contains(size),
            let data = try? Data(contentsOf: archive), Self.matches(data, digest: manifest.sha256)
        else { return nil }
        return BrowserContentPackage(manifest: manifest, archive: archive)
    }

    private func archiveURL(for manifest: BrowserContentPackage.Manifest) -> URL {
        directory.appendingPathComponent(manifest.sha256 + ".zip")
    }

    private static func matches(_ data: Data, digest: String) -> Bool {
        (1...maximumArchiveSize).contains(data.count) && SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }.joined() == digest
    }

    private func prune(_ state: Selection) {
        let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in entries ?? [] where url.pathExtension == "zip" {
            let digest = url.deletingPathExtension().lastPathComponent
            if BrowserContentPackage.Manifest.isDigest(digest),
                digest != state.active?.sha256, digest != state.pending?.sha256
            {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
