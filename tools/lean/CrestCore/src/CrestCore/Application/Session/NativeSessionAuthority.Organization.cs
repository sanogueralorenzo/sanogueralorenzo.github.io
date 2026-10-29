using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// What a folder created without a title is called.
    internal const string NewFolderTitle = "New Folder";

    /// The name a new folder takes: `title`, which the app sends in its own
    /// language, or "New Folder" when it sends none.
    internal static string FolderTitle(string? title) => string.IsNullOrWhiteSpace(title) ? NewFolderTitle : title;

    #endregion

    #region Actions - Splits

    /// Joins `tabId` to the split of `targetId` in `edited`, the organization
    /// of `space`, and shows the joined tab in the issuing window. A copy
    /// starts from where its source's page is now; see `StartFromSourcePage`.
    internal SessionEdit Joining(SessionState basis, SpaceState space, BrowserTabCollection edited, Guid windowId, Guid tabId, Guid targetId,
        int? index, IReadOnlyList<TabPageAppearance>? appearances, DateTimeOffset now, IIdSource ids) {
        var joined = edited.JoinSplit(tabId, targetId, index, ids, now);
        foreach (var (source, copyId) in joined.Copies) StartFromSourcePage(edited.Tab(copyId), source, appearances);
        var followUp = new WindowFollowUp(IssuingWindow(windowId)).ShowTab(space.Id, joined.SelectedTab).ShowSpace(space.Id);
        return new(basis.Replacing(edited.Capture(space)), SyncStaging.Edit, followUp,
            new([.. joined.Copies.Select(pair => new SessionTabCopy(pair.Source, pair.Copy))], null));
    }

    /// `space`'s organization after `edit`, with the Space's other records kept.
    internal SessionEdit Organizing(SessionState basis, Guid spaceId, SyncStaging staging, Action<BrowserTabCollection> edit) {
        var space = Editable(basis, spaceId);
        var edited = BrowserTabCollection.Restore(space);
        edit(edited);
        return new(basis.Replacing(edited.Capture(space)), staging);
    }

    #endregion

}
