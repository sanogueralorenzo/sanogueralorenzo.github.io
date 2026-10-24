using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Transfer

    /// Moves ownership without closing, archiving, or creating a replacement tab.
    /// All destination checks precede mutation of either collection. Refused with
    /// `TabAlreadyExists` when the destination holds the tab or keeps it in its
    /// archive, `TabLimitReached` or `PinnedTabsFull` when it has no room,
    /// `UnknownFolder` for a folder the destination does not hold, and
    /// `InvalidFolderPlacement` for one outside the section or a tab named to
    /// go before itself.
    public Guid? TransferTo(BrowserTabCollection destination, Guid id, Guid? selected, Guid? fallback,
        TabPlacement? requestedPlacement, Guid? requestedFolder, Guid? before,
        bool afterSelection, Guid? destinationSelection, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(destination);
        if (ReferenceEquals(this, destination)) throw new ArgumentException("A tab moves to another Space.", nameof(destination));
        var tab = Tab(id);
        if (destination.tabs.Any(t => t.Id == id) || destination.archive.Any(archived => archived.Tab.Id == id))
            throw new Rejected(new TabAlreadyExists(id));
        if (destination.tabs.Count >= MaximumTabs) throw new Rejected(new TabLimitReached(MaximumTabs));
        var placement = requestedPlacement ?? tab.Placement;
        // A folder the move names must be there, in the section it moves to.
        if (requestedFolder is { } named && (destination.KnownFolder(named).Location != placement || !placement.HoldsFolders))
            throw new Rejected(new InvalidFolderPlacement());
        Guid? folder = requestedFolder;
        RequireRoom(placement, destination.tabs.Count(t => t.Placement == placement) + 1);
        if (before == id) throw new Rejected(new InvalidFolderPlacement());
        bool Matches(BrowserTab tab) => tab.Placement == placement && tab.FolderId == folder;
        int insertion = before is { } anchor ? destination.tabs.FindIndex(t => t.Id == anchor && Matches(t)) : -1;
        if (insertion < 0) {
            int last = destination.tabs.FindLastIndex(Matches);
            insertion = last >= 0 ? last + 1 : NextSection(destination.tabs, placement);
        }
        if (afterSelection && destination.tabs.FindIndex(t => t.Id == destinationSelection) is var origin && origin >= 0) {
            insertion = origin + 1;
            if (destination.tabs[origin].SplitGroupId is { } group)
                while (insertion < destination.tabs.Count && destination.tabs[insertion].SplitGroupId == group) insertion++;
        }
        var ordered = new FolderTree(folders).PreserveOrder([id], tabs);
        tabs.Remove(tab); folders.Clear(); folders.AddRange(ordered);
        tab.Place(placement, folder, now); tab.SetSplit(null); tab.MarkPosition(now);
        destination.tabs.Insert(insertion, tab);
        // Cross-Space organization retains a singleton's stored membership,
        // as checkpoint repair does for incomplete sync batches. A window
        // transfer explicitly detaches and normalizes its source run.
        if (afterSelection) NormalizeSplits(now); else RepairSplitMembership();
        destination.RepairSplitMembership();
        return selected == id ? fallback is { } next && tabs.Any(t => t.Id == next) ? next : null : selected;
    }

    #endregion
}
