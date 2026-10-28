namespace CrestCore.Application;

/// How soon an accepted edit reaches the sync journal.
///
/// Edits that do not wait for disk queue a stage on the stager's worker, and a
/// stage queued later replaces one that has not committed, so a burst of edits
/// stages once, with the newest session and the newest edit's reason. An edit
/// that waits for disk stages from its own proposed session while its revision
/// is reserved, and the file takes the session and the journal together.
///
/// Staging projects the whole session, so an edit as frequent as showing a tab
/// waits long enough for many to share one stage. Nothing is lost by waiting:
/// an upload, backgrounding and quitting each settle every queued stage first.
internal sealed class SyncUrgency {
    #region Variables

    /// Staged once edits pause: a drag or a rename.
    public static readonly SyncUrgency Coalesced = new(delay: TimeSpan.FromMilliseconds(150), durability: Durability.WriteBehind);
    /// Staged once the browser has been quiet for a while, and at the latest a
    /// few minutes after the first such edit: a tab shown or a page report,
    /// which another device need not see soon.
    public static readonly SyncUrgency Deferred = new(delay: TimeSpan.FromSeconds(30), durability: Durability.WriteBehind,
        maximumWait: TimeSpan.FromMinutes(5));
    /// Staged as soon as the worker is free: a new tab, folder or Space, and deletions.
    public static readonly SyncUrgency Immediate = new(delay: TimeSpan.Zero, durability: Durability.WriteBehind);
    /// Staged with the edit and saved with it before the command returns: Space
    /// deletion, imports, batches and moves between Spaces or workspaces,
    /// which an upload or an engine's data erasure follows.
    public static readonly SyncUrgency WithSave = new(delay: TimeSpan.Zero, durability: Durability.BeforeReturn);

    public static IReadOnlyList<SyncUrgency> All { get; } = [Coalesced, Deferred, Immediate, WithSave];

    /// How long a queued stage waits for a later edit to replace it.
    public TimeSpan Delay { get; }

    /// The longest a stage waits after the first edit it covers, however often
    /// later edits replace it; null when each edit may postpone it again.
    public TimeSpan? MaximumWait { get; }

    /// When the edit's revision is on disk, which is when its journal is too.
    public Durability Durability { get; }

    /// Whether the edit stages inside its own save instead of on the worker.
    public bool StagesWithSave => Durability.WaitsForDisk;

    #endregion

    #region Constructors

    private SyncUrgency(TimeSpan delay, Durability durability, TimeSpan? maximumWait = null) {
        Delay = delay;
        Durability = durability;
        MaximumWait = maximumWait;
    }

    #endregion
}
