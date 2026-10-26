namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Split metadata

    /// A split copied into new tabs keeps its name, icon and tint, each recorded
    /// as chosen now so the copy's fields win over nothing older.
    public void CopySplitMetadata(Guid source, Guid copy, DateTimeOffset now) {
        if (splitGroups.FirstOrDefault(group => group.Id == source) is not { } metadata) return;
        var changedAt = BrowserEditTimestamp.Normalize(now);
        splitGroups.Add(metadata with { Id = copy, TitleModifiedAt = changedAt, IconModifiedAt = changedAt, TintModifiedAt = changedAt });
    }

    /// Drops what was chosen for splits no tab belongs to any longer.
    public void PruneSplitMetadata() {
        var retained = tabs.Where(tab => tab.SplitGroupId is not null).Select(tab => tab.SplitGroupId!.Value).ToHashSet();
        splitGroups.RemoveAll(group => !retained.Contains(group.Id));
    }

    #endregion
}
