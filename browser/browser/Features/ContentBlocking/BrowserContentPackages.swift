import CryptoKit
import Foundation

struct BrowserContentPackage: Sendable {
    struct Manifest: Codable, Sendable {
        let version: String
        let upstreamSHA256: String
        let sha256: String

        var isSupported: Bool {
            BrowserContentPackage.isVersion(version) && BrowserContentPackage.isDigest(upstreamSHA256)
                && BrowserContentPackage.isDigest(sha256)
        }
    }

    let manifest: Manifest
    let archive: URL

    static func isVersion(_ version: String) -> Bool {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 3
            && components.allSatisfy { !$0.isEmpty && $0.count <= 8 && $0.utf8.allSatisfy { (48...57).contains($0) } }
    }

    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

actor BrowserContentPackages {
    static let maximumArchiveSize = 32 * 1_024 * 1_024

    private struct Selection: Codable {
        var active: BrowserContentPackage.Manifest?
        var pending: BrowserContentPackage.Manifest?
    }

    private let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("Selection.json") }

    init(profile: URL) {
        directory = profile.appendingPathComponent("ContentBlocking/Packages", isDirectory: true)
    }

    func available() -> (active: BrowserContentPackage?, pending: BrowserContentPackage?) {
        let state = selection()
        prune(state)
        if let pending = state.pending { return (nil, verified(pending)) }
        return (verified(state.active), nil)
    }

    func stage(_ release: BrowserContentRelease, data: Data) throws -> BrowserContentPackage {
        guard data.count == release.size, BrowserContentPackage.digest(data) == release.sha256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let prepared = try BrowserContentPackagePreparation.prepare(data, version: release.version)
        let manifest = BrowserContentPackage.Manifest(
            version: release.version, upstreamSHA256: release.sha256, sha256: BrowserContentPackage.digest(prepared))
        try Task.checkCancellation()
        try createDirectory()
        let archive = archiveURL(for: manifest)
        try prepared.write(to: archive, options: .atomic)
        var state = selection()
        state.pending = manifest
        try save(state)
        return BrowserContentPackage(manifest: manifest, archive: archive)
    }

    func activate(_ package: BrowserContentPackage) throws {
        let state = Selection(active: package.manifest)
        try save(state)
        prune(state)
    }

    func discard() throws {
        let state = Selection()
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

    private func verified(_ manifest: BrowserContentPackage.Manifest?) -> BrowserContentPackage? {
        guard let manifest, manifest.isSupported else { return nil }
        let archive = archiveURL(for: manifest)
        guard let values = try? archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
            values.isRegularFile == true, values.isSymbolicLink != true,
            let size = values.fileSize, (1...Self.maximumArchiveSize).contains(size),
            let data = try? Data(contentsOf: archive), BrowserContentPackage.digest(data) == manifest.sha256
        else { return nil }
        return BrowserContentPackage(manifest: manifest, archive: archive)
    }

    private func archiveURL(for manifest: BrowserContentPackage.Manifest) -> URL {
        directory.appendingPathComponent(manifest.sha256 + ".zip")
    }

    private func prune(_ state: Selection) {
        let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in entries ?? [] where url.pathExtension == "zip" {
            let digest = url.deletingPathExtension().lastPathComponent
            if BrowserContentPackage.isDigest(digest),
                digest != state.active?.sha256, digest != state.pending?.sha256
            {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
