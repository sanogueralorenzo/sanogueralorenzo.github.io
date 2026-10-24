import Dispatch
import Foundation

/// Stores each tab's favicon as its own file, off the main thread.
///
/// Files rather than a `UserDefaults` dictionary: `UserDefaults` is read into
/// every process wholesale and written through `cfprefsd`, and one dictionary
/// value would have to be re-encoded in full for each captured icon — the same
/// whole-blob rewrite this split exists to end. A file per tab makes a capture
/// touch exactly one small file, and it matches the tab-state archive that
/// already stores per-tab blobs this way.
///
/// Not partitioned by profile, unlike that archive: nothing here is keyed or
/// queryable by Space, so a Space can only ask for the tab IDs it owns, and the
/// tabs of a deleted Space or closed tabs leave the live set — which is what the
/// sweep keys on.
final class BrowserFaviconFileStore: BrowserFaviconStoring, @unchecked Sendable {
    /// The cap a capture already enforces, re-enforced here so a favicon that
    /// arrived some other way cannot grow the store without bound.
    static let defaultMaximumFaviconByteCount = BrowserFaviconCapture.maximumByteCount
    static let directoryName = "Favicons"
    static let fileExtension = "favicon"

    let rootDirectory: URL

    private let maximumFaviconByteCount: Int
    private let writeQueue: DispatchQueue
    private let fileManager = FileManager.default

    /// The production store, or nil when this process has no usable Application
    /// Support directory. A nil store means favicons live only in memory for the
    /// run rather than failing a launch.
    static func production() -> BrowserFaviconFileStore? {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else { return nil }
        return BrowserFaviconFileStore(
            rootDirectory:
                applicationSupport
                .appendingPathComponent(
                    ProductIdentity.storageDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(directoryName, isDirectory: true)
        )
    }

    init(
        rootDirectory: URL,
        maximumFaviconByteCount: Int = BrowserFaviconFileStore
            .defaultMaximumFaviconByteCount
    ) {
        precondition(maximumFaviconByteCount > 0)
        self.rootDirectory = rootDirectory
        self.maximumFaviconByteCount = maximumFaviconByteCount
        writeQueue = DispatchQueue(
            label: "com.pauldavis.crest.favicon-store",
            qos: .utility
        )
    }

    func faviconFileURL(tabID: UUID) -> URL {
        rootDirectory
            .appendingPathComponent(tabID.uuidString)
            .appendingPathExtension(Self.fileExtension)
    }

    /// Reads on the write queue so an icon stored a moment ago is visible and a
    /// read never races a half-written file.
    func favicon(tabID: UUID) -> Data? {
        let url = faviconFileURL(tabID: tabID)
        return writeQueue.sync {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            return data
        }
    }

    func reconcile(_ faviconData: Data?, tabID: UUID) {
        let url = faviconFileURL(tabID: tabID)
        writeQueue.async { [self] in
            guard let faviconData,
                !faviconData.isEmpty,
                faviconData.count <= maximumFaviconByteCount
            else { return }
            // Comparing against the file is what keeps a full save cheap: a save
            // that changed no icon rewrites nothing, and no digest has to be
            // cached in memory to know that.
            guard (try? Data(contentsOf: url)) != faviconData else { return }
            try? fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true
            )
            try? faviconData.write(to: url, options: .atomic)
        }
    }

    func pruneFavicons(keeping tabIDs: Set<UUID>) {
        writeQueue.async { [self] in
            let retainedNames = Set(tabIDs.map(\.uuidString))
            for url in faviconFiles()
            where !retainedNames.contains(url.deletingPathExtension().lastPathComponent) {
                try? fileManager.removeItem(at: url)
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

    private func faviconFiles() -> [URL] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        return contents.filter { $0.pathExtension == Self.fileExtension }
    }
}
