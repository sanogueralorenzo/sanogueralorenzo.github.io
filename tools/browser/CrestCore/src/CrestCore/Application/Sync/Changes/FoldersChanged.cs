namespace CrestCore.Contracts;

/// <summary>
/// A Space's folders changed. <see cref="Removed"/> folders are gone. Each folder in
/// <see cref="Updated"/> replaces the folder with its identity where that folder
/// stands, or goes after the others when it is new. <see cref="Order"/> names every
/// folder in its new order, and is present only when that order differs from the one
/// those steps leave.
/// </summary>
public sealed record FoldersChanged(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<FolderState> Updated,
    IReadOnlyList<Guid> Removed, IReadOnlyList<Guid>? Order) : Change {
    #region Actions - Sync

    /// The records of the folders it removed.
    internal override IEnumerable<string> RemovedRecords(SessionState previous) => Removed.Select(SyncRecordKind.Folder.RecordName);

    #endregion
}
