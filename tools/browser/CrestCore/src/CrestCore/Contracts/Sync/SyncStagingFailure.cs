namespace CrestCore.Contracts;

/// Why the core could not stage the session's edits for sync. The session
/// itself is unaffected; the next edit stages everything again.
///
/// A failure travels as its index in `All`, so `All` is append-only.
public sealed class SyncStagingFailure {
    #region Variables

    /// The session has more records than sync carries, or its journal would
    /// outgrow the size sync keeps.
    public static readonly SyncStagingFailure TooLarge = new(name: "tooLarge",
        title: "This browsing session is too large to sync.");
    /// A record in the session cannot be written for sync, such as two records
    /// with one identity or folders nested inside each other.
    public static readonly SyncStagingFailure InvalidSession = new(name: "invalidSession",
        title: "Some of this browsing session can’t be synced.");
    /// The journal has issued every version it can.
    public static readonly SyncStagingFailure ClockExhausted = new(name: "clockExhausted",
        title: "Sync can’t record more changes on this device.");
    /// The journal could not be saved with the session.
    public static readonly SyncStagingFailure NotSaved = new(name: "notSaved",
        title: "Changes couldn’t be saved for sync.");

    public static IReadOnlyList<SyncStagingFailure> All { get; } = [TooLarge, InvalidSession, ClockExhausted, NotSaved];

    public string Name { get; }

    /// What sync settings say about the failure.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SyncStagingFailure(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SyncStagingFailure? Named(string? name) => All.FirstOrDefault(failure => failure.Name == name);

    #endregion
}
