import CryptoKit
import Dispatch
import Foundation

final class BrowserTabStateArchive: BrowserTabStateArchiving, @unchecked Sendable {
    /// One tab's framed state may not exceed this. A page with an enormous
    /// back/forward list is worth less than the disk and main-thread read it
    /// would cost, so it falls back to a plain reload.
    static let defaultMaximumStateByteCount = 4 * 1024 * 1024
    /// How many tabs one profile may keep state for. Beyond this the
    /// least-recently-written states are dropped.
    static let defaultMaximumStatesPerProfile = 100
    static let directoryName = "TabState"
    static let fileExtension = "webarchive-state"

    let rootDirectory: URL

    private let maximumStateByteCount: Int
    private let maximumStatesPerProfile: Int
    private let writeQueue: DispatchQueue
    private let fileManager = FileManager.default

    /// The production archive, or nil when this process has no usable
    /// Application Support directory. A nil archive turns the feature off rather
    /// than failing a launch.
    static func production() -> BrowserTabStateArchive? {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else { return nil }
        return BrowserTabStateArchive(
            rootDirectory:
                applicationSupport
                .appendingPathComponent(
                    ProductIdentity.storageDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(directoryName, isDirectory: true)
        )
    }

    static func forLaunch(_ environment: BrowserLaunchEnvironment) -> BrowserTabStateArchive? {
        guard environment.requiresIsolation else { return production() }
        guard !environment.isXCTestRuntime, !environment.isSwiftUIPreviewRuntime,
            let identity = environment.persistentIsolationID,
            let base = production()?.rootDirectory
        else { return nil }
        let namespace = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return BrowserTabStateArchive(
            rootDirectory:
                base
                .appendingPathComponent("Isolated", isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true))
    }

    init(
        rootDirectory: URL,
        maximumStateByteCount: Int = BrowserTabStateArchive.defaultMaximumStateByteCount,
        maximumStatesPerProfile: Int = BrowserTabStateArchive.defaultMaximumStatesPerProfile
    ) {
        precondition(maximumStateByteCount > 0)
        precondition(maximumStatesPerProfile > 0)
        self.rootDirectory = rootDirectory
        self.maximumStateByteCount = maximumStateByteCount
        self.maximumStatesPerProfile = maximumStatesPerProfile
        writeQueue = DispatchQueue(
            label: "com.pauldavis.crest.tab-state-archive",
            qos: .utility
        )
    }

    func directory(profileID: UUID) -> URL {
        rootDirectory.appendingPathComponent(profileID.uuidString, isDirectory: true)
    }

    func stateFileURL(profileID: UUID, tabID: UUID) -> URL {
        directory(profileID: profileID)
            .appendingPathComponent(tabID.uuidString)
            .appendingPathExtension(Self.fileExtension)
    }

    /// Reads on the write queue so a state archived a moment ago is visible, and
    /// so a read never races a half-written file.
    func archivedState(profileID: UUID, tabID: UUID) -> Data? {
        let url = stateFileURL(profileID: profileID, tabID: tabID)
        return writeQueue.sync { try? Data(contentsOf: url) }
    }

    func archive(interactionState: Data, url: URL?, history: Data?, profileID: UUID, tabID: UUID) {
        guard !interactionState.isEmpty || history != nil else { return }
        var encoded = BrowserTabStateEnvelope(interactionState: interactionState, url: url, history: history).encoded()
        // The engine history matters most: past the limit the core's history
        // goes first, and the tab relaunches with what its engine kept.
        if encoded.count > maximumStateByteCount, history != nil, !interactionState.isEmpty {
            encoded = BrowserTabStateEnvelope(interactionState: interactionState, url: url).encoded()
        }
        guard encoded.count <= maximumStateByteCount else {
            // An oversized state must not leave an older, smaller one behind:
            // that stale state would restore a page the tab has moved past.
            removeState(profileID: profileID, tabID: tabID)
            return
        }
        let destination = stateFileURL(profileID: profileID, tabID: tabID)
        let directory = directory(profileID: profileID)
        writeQueue.async { [self] in
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try? encoded.write(to: destination, options: .atomic)
            enforceProfileLimit(in: directory)
        }
    }

    func removeState(profileID: UUID, tabID: UUID) {
        let url = stateFileURL(profileID: profileID, tabID: tabID)
        writeQueue.async { [self] in
            try? fileManager.removeItem(at: url)
        }
    }

    func removeStates(profileID: UUID) {
        let directory = directory(profileID: profileID)
        writeQueue.async { [self] in
            try? fileManager.removeItem(at: directory)
        }
    }

    func pruneStates(keeping tabIDsByProfileID: [UUID: Set<UUID>]) {
        writeQueue.async { [self] in
            for (profileID, tabIDs) in tabIDsByProfileID {
                let directory = directory(profileID: profileID)
                let retainedNames = Set(tabIDs.map(\.uuidString))
                for url in stateFiles(in: directory)
                where !retainedNames.contains(url.deletingPathExtension().lastPathComponent) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }

    func flushPendingWrites() async {
        await withCheckedContinuation { continuation in
            writeQueue.async {
                continuation.resume()
            }
        }
    }

    private func enforceProfileLimit(in directory: URL) {
        let files = stateFiles(in: directory)
        guard files.count > maximumStatesPerProfile else { return }
        let ordered =
            files
            .map { url in
                (
                    url: url,
                    modifiedAt:
                        (try? url.resourceValues(
                            forKeys: [.contentModificationDateKey]
                        ).contentModificationDate) ?? .distantPast
                )
            }
            .sorted { $0.modifiedAt < $1.modifiedAt }
        for entry in ordered.prefix(files.count - maximumStatesPerProfile) {
            try? fileManager.removeItem(at: entry.url)
        }
    }

    private func stateFiles(in directory: URL) -> [URL] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        return contents.filter { $0.pathExtension == Self.fileExtension }
    }
}
