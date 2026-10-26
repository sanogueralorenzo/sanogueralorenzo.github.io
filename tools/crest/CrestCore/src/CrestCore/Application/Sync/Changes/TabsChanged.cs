namespace CrestCore.Contracts;

/// <summary>
/// A Space's tabs changed. <see cref="Removed"/> tabs are gone. Each tab in
/// <see cref="Updated"/> replaces the tab with its identity where that tab stands, or
/// goes after the others when it is new. <see cref="Order"/> names every tab in its
/// new order, and is present only when that order differs from the one those steps
/// leave.
/// </summary>
public sealed record TabsChanged(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<TabState> Updated, IReadOnlyList<Guid> Removed,
    IReadOnlyList<Guid>? Order) : Change {
    #region Actions - Sync

    /// The records of the tabs it removed.
    internal override IEnumerable<string> RemovedRecords(SessionState previous) => Removed.Select(SyncRecordKind.Tab.RecordName);

    #endregion
}
