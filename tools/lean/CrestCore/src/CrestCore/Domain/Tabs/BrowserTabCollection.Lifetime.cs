using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Lifetime

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

    #endregion
}
