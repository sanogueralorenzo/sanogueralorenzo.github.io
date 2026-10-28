import Foundation

@testable import Crest

/// What an installed release before the core's session file left behind, for
/// the upgrade tests and the stored-session harness to carry. Such a release
/// kept the session in the form the core's file still keeps it, so a staging
/// file of the core's writes it.
enum BrowserInstalledRelease {
    // MARK: - Types

    /// A session in the form an installed release kept it: the session
    /// without history or images, and each Space's history beside it.
    struct Parts {
        let core: Data
        let history: [LegacyHistory]
    }

    // MARK: - Actions

    /// The session a core opens from `seed`, or without one the session a
    /// first launch starts with, in the form an installed release kept it.
    @MainActor
    static func parts(of seed: SessionState.Seed?) throws -> Parts {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let staging = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
            try staging.send(AdoptLegacySession(installed: .nothing, seed: seed))
        }
        let parts = try BrowserStoredSessionHarness.parts(in: directory)
        guard let core = parts["core"] else { throw BrowserStoredSessionHarness.HarnessError.missingPart("core") }
        let prefix = "history."
        return Parts(
            core: core,
            history: parts.compactMap { part, entries in
                guard part.hasPrefix(prefix), let spaceID = UUID(uuidString: String(part.dropFirst(prefix.count)))
                else { return nil }
                return LegacyHistory(spaceID: spaceID, entries: entries)
            })
    }

    /// Writes the session a core opens from `seed` the way such a release
    /// kept it: the session under its core key, each Space's history under a
    /// key of its own, and the image `images` holds for each tab in
    /// `favicons`.
    @MainActor
    static func write(
        _ seed: SessionState.Seed, images: [UUID: Data] = [:], to defaults: UserDefaults,
        favicons: any BrowserFaviconStoring
    ) throws {
        let parts = try parts(of: seed)
        defaults.set(parts.core, forKey: BrowserLegacySessionDefaults.coreKey)
        for history in parts.history {
            defaults.set(
                history.entries, forKey: BrowserLegacySessionDefaults.historyKeyPrefix + history.spaceID.uuidString)
        }
        for (tabID, image) in images { favicons.reconcile(image, tabID: tabID) }
    }

    /// Gives a new file the session a core opens from `seed`, or without one
    /// the session a first launch starts with, as its first session, the way
    /// a launch carries an installed release's session with the journal
    /// `journalData` holds. A seed alone carries no journal, so with one the
    /// session goes in the installed form.
    @MainActor
    static func adopt(_ seed: SessionState.Seed?, journalData: Data?, into core: CrestCore) throws {
        guard let journalData else {
            try core.send(AdoptLegacySession(installed: .nothing, seed: seed))
            return
        }
        let parts = try parts(of: seed)
        try core.send(
            AdoptLegacySession(
                installed: LegacySession(
                    core: parts.core, wholeGraph: nil, history: parts.history, journal: journalData),
                seed: nil))
    }
}

extension LegacySession {
    /// An installed release that kept nothing.
    static let nothing = LegacySession(core: nil, wholeGraph: nil, history: [], journal: nil)
}
