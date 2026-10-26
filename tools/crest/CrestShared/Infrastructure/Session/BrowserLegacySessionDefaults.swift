import Foundation

/// What the installed releases before the core's session file kept in their
/// defaults, read raw for the core to carry into its file once. Reading the
/// values is this platform's part; the core decodes every one of them. Nothing
/// writes them any more, so a rollback to such a release still finds them.
struct BrowserLegacySessionDefaults {
    // MARK: - Variables

    /// The session without its history or images, which the releases that
    /// split the session wrote.
    static let coreKey = "crest.session.v2"
    /// The whole-graph session every release before that split wrote.
    static let wholeGraphKey = "crest.session.v1"
    /// Each Space's history beside the core, one key per Space.
    static let historyKeyPrefix = "crest.history.v1."
    /// The Spaces that had a history key; not a history of its own.
    static let historyIndexKey = "crest.history.v1.index"
    static let journalKey = "crest.sync.journal.v1"
    /// The suite the sync journal moved to. Releases before the move kept it
    /// in the standard defaults.
    static let journalSuiteName = "com.pauldavis.crest.sync-journal"

    private let defaults: UserDefaults
    /// Where the journal may be, in the order the installed release looked.
    private let journalDefaults: [UserDefaults]

    /// Everything the core needs to carry. The whole graph is read only when
    /// no split core exists, because the core ignores it then.
    var values: LegacySession {
        let core = defaults.data(forKey: Self.coreKey)
        return LegacySession(
            core: core,
            wholeGraph: core == nil ? defaults.data(forKey: Self.wholeGraphKey) : nil,
            history: core == nil ? [] : history,
            journal: journalDefaults.lazy.compactMap { $0.data(forKey: Self.journalKey) }.first)
    }

    private var history: [LegacyHistory] {
        defaults.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix(Self.historyKeyPrefix), key != Self.historyIndexKey,
                let spaceID = UUID(uuidString: String(key.dropFirst(Self.historyKeyPrefix.count))),
                let entries = value as? Data
            else { return nil }
            return LegacyHistory(spaceID: spaceID, entries: entries)
        }
    }

    // MARK: - Initializers

    /// The installed app's own defaults, with the journal in its suite or,
    /// before the journal moved, beside the session.
    static var installed: Self {
        Self(
            defaults: .standard,
            journalDefaults: [UserDefaults(suiteName: journalSuiteName), .standard].compactMap(\.self))
    }

    /// `defaults` holds the session and its history; `journalDefaults` are
    /// searched in order for the journal, and an empty list carries none.
    init(defaults: UserDefaults, journalDefaults: [UserDefaults]) {
        self.defaults = defaults
        self.journalDefaults = journalDefaults
    }
}
