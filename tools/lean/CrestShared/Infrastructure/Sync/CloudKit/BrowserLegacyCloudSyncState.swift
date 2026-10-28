import CryptoKit
import Foundation

/// Where an installed release kept the cloud transport's state, read once so
/// the core can adopt it into its device store: a file under Application
/// Support, or before that a blob in the defaults. Nothing here writes or
/// removes either, so a release from before this one still reads them.
@MainActor
struct BrowserLegacyCloudSyncState {
    // MARK: - Static Variables

    static let directoryName = "CloudSync"
    static let fileName = "state.v1.json"
    /// The defaults key the oldest releases kept the state under.
    static let defaultsKey = "crest.cloud-sync.state.v1"

    // MARK: - Variables

    /// The file the state was kept in, when there is one to look for.
    let fileURL: URL?
    /// The defaults the oldest releases kept it in before the file.
    let defaults: UserDefaults?

    // MARK: - Initializers

    /// The production state: the file under Application Support, or the
    /// defaults blob `defaults` kept before it.
    static func production(defaults: UserDefaults = .standard) -> BrowserLegacyCloudSyncState {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        return BrowserLegacyCloudSyncState(fileURL: directory?.appendingPathComponent(fileName), defaults: defaults)
    }

    /// The state an isolated launch kept for `configuration`'s zone.
    static func isolated(localProfileID: String, configuration: BrowserCloudSyncConfiguration)
        -> BrowserLegacyCloudSyncState
    {
        let identity = [localProfileID, configuration.containerIdentifier, configuration.zoneName].joined(
            separator: "\n")
        let namespace = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("Isolated", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(fileName)
        return BrowserLegacyCloudSyncState(fileURL: file, defaults: nil)
    }

    // MARK: - Actions - Reading

    /// The state exactly as it was kept, or nil when there is none.
    func read() -> Data? {
        if let fileURL, let data = try? Data(contentsOf: fileURL) { return data }
        return defaults?.data(forKey: Self.defaultsKey)
    }
}
