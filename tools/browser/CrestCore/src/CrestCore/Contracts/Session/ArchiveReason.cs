namespace CrestCore.Contracts;

/// Why a tab moved to its Space's archive.
///
/// Synced archive records spell a reason as its `Name`. The stored session
/// spells it as its `StoredReason`, which builds from before deletion audits
/// still read, and marks the two deletions with their `DeletionOrigin`. None of
/// these spellings ever changes. A reason travels as its index in `All`, so
/// `All` is append-only.
public sealed class ArchiveReason {
    #region Variables

    /// Current-tab cleanup archived a tab nobody had used for its lifetime.
    public static readonly ArchiveReason AutoCleanup = new(name: "autoCleanup", storedReason: "autoCleanup",
        filterGroup: ArchiveFilterGroup.Automatic, title: "Automatically cleaned", symbol: "archivebox.fill", tint: SystemTint.Orange,
        isCleanup: true);
    public static readonly ArchiveReason Closed = new(name: "closed", storedReason: "closed", filterGroup: ArchiveFilterGroup.Closed,
        title: "Closed", symbol: "xmark.circle.fill", tint: SystemTint.Red);
    /// A saved or pinned tab the person deleted. Unlike a close, this is the
    /// evidence that authorizes an explicit sync deletion.
    public static readonly ArchiveReason Deleted = new(name: "deleted", storedReason: "closed", deletionOrigin: "local",
        filterGroup: ArchiveFilterGroup.Closed, title: "Deleted", symbol: "trash.fill", tint: SystemTint.Red, isExplicitDeletion: true);
    /// An explicit deletion first confirmed by another device. Synced records
    /// carry it back as the deletion it stands for, never as a new cause.
    public static readonly ArchiveReason DeletedOnAnotherDevice = new(name: "deletedOnAnotherDevice", storedReason: "synced",
        deletionOrigin: "remote", filterGroup: ArchiveFilterGroup.Synced, title: "Deleted on another device", symbol: "trash.fill",
        tint: SystemTint.Red, isExplicitDeletion: true, isReceived: true, syncProjection: (_, _) => Deleted.Name);
    public static readonly ArchiveReason QuickWindow = new(name: "quickWindow", storedReason: "quickWindow",
        filterGroup: ArchiveFilterGroup.QuickWindow, title: "Quick Window", symbol: "timer", tint: SystemTint.Purple);
    /// An archive record first observed from another device. This is how the
    /// record looks here, so a synced record keeps the cause the shared record
    /// carried, or says closed when it carried none.
    public static readonly ArchiveReason Synced = new(name: "synced", storedReason: "synced", filterGroup: ArchiveFilterGroup.Synced,
        title: "Synced from another device", symbol: "icloud.and.arrow.down.fill", tint: SystemTint.Blue, isReceived: true,
        syncProjection: (self, shared) => Named(shared) is { } cause
            ? cause == self ? Closed.Name : cause.SyncProjection(null)
            : shared ?? Closed.Name);

    public static IReadOnlyList<ArchiveReason> All { get; } = [AutoCleanup, Closed, Deleted, DeletedOnAnotherDevice, QuickWindow, Synced];

    private readonly Func<ArchiveReason, string?, string> syncProjection;

    public string Name { get; }

    /// The `reason` the stored session writes, which builds from before
    /// deletion audits can read.
    public string StoredReason { get; }

    /// The stored session's `deletionOrigin` for a deletion, which recovers the
    /// reason that `StoredReason` alone cannot.
    public string? DeletionOrigin { get; }

    /// The filter of the archive list that shows the reason.
    public ArchiveFilterGroup FilterGroup { get; }

    /// What the archive list says about the tab.
    [Localized]
    public string Title { get; }

    /// The SF Symbol the archive list shows beside the tab.
    public string Symbol { get; }

    /// The color of the symbol.
    public SystemTint Tint { get; }

    /// The person deleted the tab, which authorizes deleting its synced record.
    public bool IsExplicitDeletion { get; }

    /// Cleanup archived the tab for going unused, so using it again on another
    /// device keeps it.
    public bool IsCleanup { get; }

    /// How a record another device archived reads here.
    public bool IsReceived { get; }

    #endregion

    #region Constructors

    private ArchiveReason(string name, string storedReason, ArchiveFilterGroup filterGroup, string title, string symbol, SystemTint tint,
        string? deletionOrigin = null, bool isExplicitDeletion = false, bool isCleanup = false, bool isReceived = false,
        Func<ArchiveReason, string?, string>? syncProjection = null) {
        Name = name;
        StoredReason = storedReason;
        DeletionOrigin = deletionOrigin;
        FilterGroup = filterGroup;
        Title = title;
        Symbol = symbol;
        Tint = tint;
        IsExplicitDeletion = isExplicitDeletion;
        IsCleanup = isCleanup;
        IsReceived = isReceived;
        this.syncProjection = syncProjection ?? ((self, _) => self.Name);
    }

    #endregion

    #region Actions - Lookup

    public static ArchiveReason? Named(string? name) => All.FirstOrDefault(reason => reason.Name == name);

    /// The reason a stored archive record names: its deletion origin decides a
    /// deletion, and otherwise its reason does. Null for a spelling this build
    /// does not know.
    public static ArchiveReason? Stored(string? reason, string? deletionOrigin) =>
        All.FirstOrDefault(known => known.DeletionOrigin is not null && known.DeletionOrigin == deletionOrigin) ?? Named(reason);

    #endregion

    #region Actions - Sync

    /// How a record another device archived reads here: as a deletion confirmed
    /// elsewhere when it was an explicit deletion, or as synced.
    public static ArchiveReason Received(bool explicitDeletion) =>
        All.First(reason => reason.IsReceived && reason.IsExplicitDeletion == explicitDeletion);

    /// The reason a synced archive record carries for this one, given the one
    /// the shared record carried before, if any. A shared reason this build
    /// does not know is kept as it is.
    public string SyncProjection(string? shared) => syncProjection(this, shared);

    #endregion
}
