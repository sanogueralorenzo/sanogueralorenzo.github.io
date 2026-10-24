namespace CrestCore.Contracts;

/// <summary>
/// A Space's archive changed. The archived tabs <see cref="Removed"/> names are gone.
/// Each entry in <see cref="Archived"/> replaces the entry for its tab where that
/// entry stands, or goes after the others when it is new. <see cref="Order"/> names
/// every archived tab in its new order, and is present only when that order differs
/// from the one those steps leave.
/// </summary>
public sealed record ArchiveChanged(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<ArchivedTabState> Archived,
    IReadOnlyList<Guid> Removed, IReadOnlyList<Guid>? Order) : Change {
    #region Actions - Sync

    /// The records of the archived tabs it removed.
    internal override IEnumerable<string> RemovedRecords(SessionState previous) => Removed.Select(SyncRecordKind.Archive.RecordName);

    #endregion
}
