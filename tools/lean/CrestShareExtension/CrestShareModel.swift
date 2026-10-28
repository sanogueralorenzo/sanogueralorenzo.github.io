import Foundation
import Observation
import UniformTypeIdentifiers

/// What the share sheet's Crest entry is doing with what another app shared:
/// reading its web link and handing it to Crest, or saying why it could not.
@Observable
@MainActor
final class CrestShareModel {
    // MARK: - Types

    /// What the share sheet says when it opens no link.
    struct Notice: Sendable {
        static let noLink = Notice(title: "No Link to Open", systemImage: "link")
        static let couldNotOpen = Notice(title: "Couldn’t Open Crest", systemImage: "exclamationmark.triangle")

        let title: LocalizedStringResource
        let systemImage: String
    }

    // MARK: - Variables

    /// What the sheet says, or nil while it reads and hands on the link.
    private(set) var notice: Notice?

    private let open: @MainActor (URL) async -> Bool
    private let finish: @MainActor () -> Void

    // MARK: - Initializers

    init(open: @escaping @MainActor (URL) async -> Bool, finish: @escaping @MainActor () -> Void) {
        self.open = open
        self.finish = finish
    }

    // MARK: - Actions - Sharing

    /// Reads the web link from what another app shared and hands it to
    /// Crest, which routes it as it would any link another app opens.
    func receive(_ providers: [NSItemProvider]) async {
        guard let link = await Self.sharedLink(in: providers) else {
            notice = .noLink
            return
        }
        guard await open(link.handOffURL) else {
            notice = .couldNotOpen
            return
        }
        finish()
    }

    func close() {
        finish()
    }

    // MARK: - Actions - Reading shared items

    /// The first web link among the shared items: a URL, or the first link
    /// in shared text.
    private static func sharedLink(in providers: [NSItemProvider]) async -> BrowserSharedLink? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await url(from: provider), let link = BrowserSharedLink(url: url) {
                return link
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await text(from: provider), let link = BrowserSharedLink.firstWebLink(in: text) {
                return link
            }
        }
        return nil
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    /// The text a provider holds. Safari and other apps share text as a
    /// string under the bare plain-text type, which
    /// `loadObject(ofClass: String.self)` cannot read, so this reads the data.
    private static func text(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                continuation.resume(returning: data.flatMap(Self.text(in:)))
            }
        }
    }

    /// Shared text given as data: the archived string such apps register,
    /// or plain UTF-8.
    nonisolated private static func text(in data: Data) -> String? {
        if let archived = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: data) {
            return archived as String
        }
        return String(data: data, encoding: .utf8)
    }
}
