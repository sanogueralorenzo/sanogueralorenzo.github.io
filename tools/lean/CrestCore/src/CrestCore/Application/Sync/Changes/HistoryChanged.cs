namespace CrestCore.Contracts;

/// <summary>
/// A Space's history changed. <see cref="Removed"/> entries are gone. The entries in
/// <see cref="Recorded"/>, newest first, replace the entries with their identities
/// and go before every other entry. <see cref="Order"/> names every entry in its new
/// order, and is present only when that order differs from the one those steps leave.
/// </summary>
public sealed record HistoryChanged(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<HistoryEntryState> Recorded,
    IReadOnlyList<Guid> Removed, IReadOnlyList<Guid>? Order) : Change {
    #region Actions - Sync

    /// The records of the history entries it removed.
    internal override IEnumerable<string> RemovedRecords(SessionState previous) => Removed.Select(SyncRecordKind.History.RecordName);

    #endregion
}
