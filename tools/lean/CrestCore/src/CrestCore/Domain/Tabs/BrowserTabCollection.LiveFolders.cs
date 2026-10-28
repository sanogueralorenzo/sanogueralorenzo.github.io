using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Live folders

    public void SetGitHubLiveFolderOptions(Guid id, GitHubLiveFolderOptions options) {
        var folder = KnownFolder(id);
        folders[folders.IndexOf(folder)] = folder with { LiveOptions = options };
    }

    public void EnableLiveFolder(Guid id, LiveFolderSource source) {
        if (folders.Any(candidate => candidate.Source == source && candidate.Id != id))
            throw new Rejected(new FolderAlreadyExists(id));
        var folder = folders.FirstOrDefault(candidate => candidate.Id == id);
        if (folder is not null && folder.Source != source) throw new Rejected(new FolderAlreadyExists(id));
        if (folder is not null && folder.Location != TabPlacement.Saved) throw new Rejected(new InvalidFolderPlacement());
        if (folder is null) {
            AddFolder(id, source.Title);
            folder = KnownFolder(id);
            folders[folders.IndexOf(folder)] = folder with { Source = source };
        }
    }

    public void RefreshLiveFolder(Guid id, LiveFolderSource source, IReadOnlyList<TabState> items, DateTimeOffset now) {
        EnableLiveFolder(id, source);
        var wanted = items.Select(item => item.SavedUrl).ToHashSet(StringComparer.Ordinal);
        var previous = tabs.Where(tab => tab.FolderId == id).ToArray();
        foreach (var tab in previous.Where(tab => !wanted.Contains(tab.SavedUrl))) {
            // Browsing away turns the page into personal work: keep it outside
            // the managed folder. Unchanged expired entries go to the archive.
            var preserve = !source.Accepts(tab.SavedUrl) || tab.State.IsAwayFromSavedAddress;
            MoveTab(tab.Id, TabPlacement.Current, null, null, detachSplit: true, now);
            if (!preserve) DismissTabs([tab.Id], null, null, now, deleting: false, ensureSelection: false, resetArchivePlacement: true);
        }
        foreach (var item in items) {
            if (previous.FirstOrDefault(tab => tab.SavedUrl == item.SavedUrl) is { } existing) {
                if (!existing.State.IsAwayFromSavedAddress) existing.ObserveAppearance(null, item.Title);
                continue;
            }
            var tab = BrowserTab.Restore(item);
            InsertTab(tab, null);
            FileTabs([tab.Id], TabPlacement.Saved, id, now, detachSplitMembers: true);
        }
    }

    #endregion
}
