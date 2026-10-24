using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Lifetime

    /// Archives a Quick Window's page as the closed open tab `closed`.
    /// Refused with `TabAlreadyExists` when the Space holds its identity.
    public void ArchiveTransient(TabState closed, DateTimeOffset now) {
        if (tabs.Any(t => t.Id == closed.Id) || archive.Any(archived => archived.Tab.Id == closed.Id))
            throw new Rejected(new TabAlreadyExists(closed.Id));
        archive.Add(new(closed, now, ArchiveReason.QuickWindow));
    }

    public BrowserTab RestoreArchived(TabState source, DateTimeOffset now) {
        var tab = BrowserTab.Restore(source with {
            Placement = TabPlacement.Current,
            FolderId = null,
            SplitGroupId = null,
            LastActivatedAt = now,
            PositionModifiedAt = BrowserEditTimestamp.Normalize(now)
        });
        InsertTab(tab, null);
        return tab;
    }

    /// Puts a saved or pinned tab's page away, returning the tab to its saved
    /// address when `returnToSavedUrl`, and answers the tab its window shows
    /// next: `fallback` in place of the tab when it showed it.
    public Guid? CloseDurable(Guid id, Guid? selected, Guid? fallback, bool returnToSavedUrl) {
        var tab = Tab(id);
        if (returnToSavedUrl) tab.ReturnToSavedUrl();
        return selected == id ? fallback is { } other && other != id && tabs.Any(t => t.Id == other)
            ? other : null : selected;
    }

    /// Archives open tabs unused for longer than `lifetime`. The tab the caller
    /// shows and any tab in `kept` (tabs other windows show) survive.
    public Guid? CleanupCurrentTabs(Guid? selected, TimeSpan lifetime, DateTimeOffset now,
        IReadOnlyCollection<Guid>? kept = null) {
        var expired = tabs.Where(t => !t.Placement.IsDurable && !t.Content.IsStartPage
            && t.Id != selected && kept?.Contains(t.Id) != true && now - t.LastActivatedAt > lifetime).ToArray();
        var ids = expired.Select(t => t.Id).ToHashSet();
        var nextFolders = new FolderTree(folders).PreserveOrder(ids, tabs);
        foreach (var tab in expired)
            archive.Add(new(tab.State with { SplitGroupId = null }, now, ArchiveReason.AutoCleanup));
        tabs.RemoveAll(t => ids.Contains(t.Id));
        folders.Clear(); folders.AddRange(nextFolders);
        // Maintenance preserves an empty selection and does not dissolve a
        // surviving split. User-driven dismissal has a different contract.
        if (selected is not null && !tabs.Any(t => t.Id == selected))
            selected = FallbackSelection();
        return selected;
    }

    #endregion
}
