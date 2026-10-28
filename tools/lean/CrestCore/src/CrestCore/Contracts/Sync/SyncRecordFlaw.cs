namespace CrestCore.Contracts;

/// Why the core cannot take records the cloud sent.
///
/// A flaw travels as its index in `All`, so `All` is append-only.
public sealed class SyncRecordFlaw {
    #region Static Variables

    /// Two records share one identity.
    public static readonly SyncRecordFlaw DuplicateRecord = new(name: "duplicateRecord",
        title: "Two records share one identity.");
    /// There are more records than sync keeps.
    public static readonly SyncRecordFlaw TooManyRecords = new(name: "tooManyRecords",
        title: "There are more records than sync keeps.");
    /// A record's contents name another record, or another Space.
    public static readonly SyncRecordFlaw IdentityMismatch = new(name: "identityMismatch",
        title: "A record’s contents don’t match its identity.");
    /// A record cannot be read: its body, a date, a placement, an identity or
    /// its deletion reason.
    public static readonly SyncRecordFlaw MalformedRecord = new(name: "malformedRecord",
        title: "A record can’t be read.");
    /// A record the journal holds in one Space arrived in another, of a kind
    /// that never moves between Spaces.
    public static readonly SyncRecordFlaw ChangedSpace = new(name: "changedSpace",
        title: "A record moved to another Space.");
    /// Folders are nested inside each other.
    public static readonly SyncRecordFlaw InvalidFolderHierarchy = new(name: "invalidFolderHierarchy",
        title: "Folders are nested inside each other.");
    /// A tab names a folder of another Space.
    public static readonly SyncRecordFlaw DanglingFolder = new(name: "danglingFolder",
        title: "A tab names a folder in another Space.");
    /// Two Spaces share a profile.
    public static readonly SyncRecordFlaw SharedProfile = new(name: "sharedProfile",
        title: "Two Spaces share a profile.");
    /// A Space arrived with another profile than the one it has here.
    public static readonly SyncRecordFlaw ProfileChanged = new(name: "profileChanged",
        title: "A Space’s profile changed.");
    /// A Space would hold more pinned tabs than it can.
    public static readonly SyncRecordFlaw TooManyPinnedTabs = new(name: "tooManyPinnedTabs",
        title: "A Space has more pinned tabs than it can hold.");
    /// Applying the records failed in a way no rule names.
    public static readonly SyncRecordFlaw Unexpected = new(name: "unexpected",
        title: "Crest hit a problem applying these records.");
    /// A snapshot holds a record this build cannot read, so it is not whole.
    public static readonly SyncRecordFlaw UnreadablePayload = new(name: "unreadablePayload",
        title: "Some iCloud records can’t be read. Update Crest on all your devices and try again.");

    public static IReadOnlyList<SyncRecordFlaw> All { get; } = [
        DuplicateRecord, TooManyRecords, IdentityMismatch, MalformedRecord, ChangedSpace, InvalidFolderHierarchy, DanglingFolder,
        SharedProfile, ProfileChanged, TooManyPinnedTabs, Unexpected, UnreadablePayload
    ];

    #endregion

    #region Variables

    public string Name { get; }

    /// What sync settings say about the flaw.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SyncRecordFlaw(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SyncRecordFlaw? Named(string? name) => All.FirstOrDefault(flaw => flaw.Name == name);

    #endregion
}
