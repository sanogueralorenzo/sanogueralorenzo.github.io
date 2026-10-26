namespace CrestCore.Contracts;

/// Why a synced record became a tombstone.
///
/// A tombstone spells its reason as the reason's `Name`, so a name never
/// changes. A reason travels as its index in `All`, so `All` is append-only.
public sealed class SyncDeletionReason {
    #region Variables

    /// The person deleted it. Only this reason deletes a Space or a folder, and
    /// it wins every conflict with an edit.
    public static readonly SyncDeletionReason ExplicitDelete = new(name: "explicitDelete", isExplicit: true);
    /// A newer local state replaced it without anybody deleting it.
    public static readonly SyncDeletionReason Superseded = new(name: "superseded", isExplicit: false);
    /// A retention rule removed it for its age.
    public static readonly SyncDeletionReason Retention = new(name: "retention", isExplicit: false);

    public static IReadOnlyList<SyncDeletionReason> All { get; } = [ExplicitDelete, Superseded, Retention];

    public string Name { get; }

    /// The person asked for the deletion, which authorizes deleting a Space or
    /// a folder and wins a conflict with an edit on another device.
    public bool IsExplicit { get; }

    #endregion

    #region Constructors

    private SyncDeletionReason(string name, bool isExplicit) {
        Name = name;
        IsExplicit = isExplicit;
    }

    #endregion

    #region Actions - Lookup

    public static SyncDeletionReason? Named(string? name) => All.FirstOrDefault(reason => reason.Name == name);

    #endregion

    #region Actions - Deletion

    // Absence alone is not authority to delete a shared record. Delivery may be
    // incomplete, and closing current tabs does not authorize deleting saved tabs.

    /// The reason a Space or folder the staged session no longer holds is
    /// deleted for, when this is the reason of the edit that removed it, or of
    /// the stage when none is known: only an explicit removal deletes one.
    internal SyncDeletionReason? ForStructure => IsExplicit ? this : null;

    /// The reason a tab the staged session no longer holds open is deleted
    /// for, when this is the reason of the edit that removed it, or null when
    /// its absence authorizes nothing: `placement` is where it was,
    /// `archiveReason` why it was archived, if it was, and
    /// `owningSpaceRemains` whether its Space stays.
    internal SyncDeletionReason? ForTab(TabPlacement? placement, ArchiveReason? archiveReason, bool owningSpaceRemains) {
        if (archiveReason?.IsExplicitDeletion == true)
            return ExplicitDelete;
        if (archiveReason is not null)
            return placement?.IsDurable != false ? null : archiveReason.IsCleanup
                ? Retention : Superseded;
        return !owningSpaceRemains && IsExplicit ? ExplicitDelete : null;
    }

    #endregion
}
