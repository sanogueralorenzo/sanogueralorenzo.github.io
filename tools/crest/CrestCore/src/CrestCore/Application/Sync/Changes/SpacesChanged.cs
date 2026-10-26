namespace CrestCore.Contracts;

/// <summary>
/// A workspace's Spaces changed membership or order. <see cref="Removed"/> Spaces are
/// gone, and each <see cref="Added"/> Space arrives whole and goes after the Spaces
/// that stay. <see cref="Order"/> names every Space in its new order, and is present
/// only when that order differs from the one those two steps leave. A Space that
/// arrives again whole is named in both <see cref="Removed"/> and <see cref="Added"/>.
/// </summary>
public sealed record SpacesChanged(Guid WorkspaceId, IReadOnlyList<SpaceState> Added, IReadOnlyList<Guid> Removed,
    IReadOnlyList<Guid>? Order) : Change {
    #region Actions - Sync

    /// A Space that is gone takes every record it held with it; one the
    /// change sends again whole names only the records it lost.
    internal override IEnumerable<string> RemovedRecords(SessionState previous) {
        foreach (var id in Removed) {
            var old = previous.Spaces.Single(space => space.Id == id);
            var resent = Added.FirstOrDefault(space => space.Id == id);
            HashSet<string> kept = resent is null ? [] : Records(resent).ToHashSet(StringComparer.Ordinal);
            if (resent is null) yield return SyncRecordKind.Space.RecordName(id);
            foreach (var name in Records(old).Where(name => !kept.Contains(name))) yield return name;
        }
    }

    /// The names of the records a Space holds besides its own.
    private static IEnumerable<string> Records(SpaceState space) =>
        space.Folders.Select(folder => SyncRecordKind.Folder.RecordName(folder.Id))
            .Concat(space.Tabs.Select(tab => SyncRecordKind.Tab.RecordName(tab.Id)))
            .Concat(space.ArchivedTabs.Select(archived => SyncRecordKind.Archive.RecordName(archived.Tab.Id)))
            .Concat(space.History.Select(entry => SyncRecordKind.History.RecordName(entry.Id)));

    #endregion
}
