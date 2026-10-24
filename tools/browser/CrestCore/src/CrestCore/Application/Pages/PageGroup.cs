using CrestCore.Contracts;

namespace CrestCore.Application;

/// One engine tab group an extension made, and the folder of the same identity
/// that shows it in its Space's open tabs. The tabs of the group's pages that
/// are open tabs of the Space file into the folder, and the folder's own
/// title, color, collapsed state and tabs are what the group holds: an edit
/// either side makes reaches the other. A grouped page whose tab the folder
/// cannot hold, a pinned or saved tab or a Quick Window's page, stays where it
/// is and stays in the group, since an extension may rely on a group it made.
///
/// A group of the persistent session outlives the engine's: the device store
/// keeps it, and once the folder's tabs have pages again after a launch the
/// engine makes the group again under the same identity, as Chrome restores a
/// group with its tabs. Any other group is memory only. Neither is synced, and
/// membership in either grants an extension nothing.
internal sealed class PageGroup {
    #region Variables

    /// The group's identity, which is also its folder's.
    public Guid Id { get; }
    public EngineKind Engine { get; }
    public Guid SpaceId { get; }

    /// The workspace that holds the group's Space: the one a page of the group
    /// reported from, or for a group the device store kept, the persistent
    /// session once it holds the Space. Null until then.
    public Guid? WorkspaceId { get; private set; }

    /// Whether the group belongs to the persistent session, which keeps it.
    public bool Persists { get; private set; }

    /// What the engine's group holds, as the core last knew: what the engine
    /// reported, or what the core asked of it since.
    private IReadOnlyList<Guid> heldPageIds = [];
    private string heldTitle;
    private TabGroupColor heldColor;
    private bool heldCollapsed;

    /// The title and color the group should have: the last the extension
    /// gave it, or the last the person gave its folder.
    private string wantedTitle;
    private TabGroupColor wantedColor;

    /// The grouped pages whose tabs the folder does not hold.
    private IReadOnlySet<Guid> outside = new HashSet<Guid>();

    /// The folder's title and color as the core last saw them. A folder that
    /// shows another was edited by the person, and the group follows.
    private string? folderTitle;
    private BrandColor? folderColor;
    /// Whether the core has seen the folder since the group was made or kept.
    private bool seesFolder;
    /// Whether the folder is made; one that went since was deleted.
    private bool showsFolder;

    #endregion

    #region Constructors

    /// A group a page of `workspaceId`'s Space `spaceId` reported, which the
    /// device store keeps when `persists`.
    public PageGroup(Guid id, EngineKind engine, Guid workspaceId, Guid spaceId, bool persists) {
        Id = id;
        Engine = engine;
        WorkspaceId = workspaceId;
        SpaceId = spaceId;
        Persists = persists;
        (heldTitle, heldColor, wantedTitle, wantedColor) = (string.Empty, TabGroupColor.Grey, string.Empty, TabGroupColor.Grey);
    }

    /// A group of the persistent session the device store kept, whose folder
    /// it shows, and which the engine holds none of yet.
    public PageGroup(TabGroupRecord record) {
        Id = record.Id;
        Engine = record.Engine;
        SpaceId = record.SpaceId;
        Persists = true;
        showsFolder = true;
        (heldTitle, heldColor, wantedTitle, wantedColor) = (record.Title, record.Color, record.Title, record.Color);
    }

    #endregion

    #region Actions - Engine

    /// What the engine reported the group became: its folder takes the title,
    /// color or collapsed state the extension changed, and open tabs move in
    /// or out as their pages joined or left the group. A page the report
    /// leaves out left the group only when it is a live page of the window
    /// the group is in; a page put away, or in another window, keeps its tab
    /// in the folder.
    public void Show(PageGroupChanged report, Pages pages) {
        if (!Located(pages) || WorkspaceId is not { } workspaceId) return;
        var reported = report.PageIds.Select(pages.Hosted).OfType<Page>()
            .Where(page => page.Engine.Kind == Engine && page.WorkspaceId == workspaceId && page.SpaceId == SpaceId).ToList();
        var made = !showsFolder;
        bool titled = made || report.Title != heldTitle, colored = made || report.Color != heldColor;
        bool collapsed = made || report.IsCollapsed != heldCollapsed;
        if (pages.Device.Attached(workspaceId) is { } workspace && Editable(workspace) is { } space) {
            var location = space.Folders.FirstOrDefault(folder => folder.Id == Id)?.Location ?? TabPlacement.Current;
            var joining = reported.Select(page => space.Tabs.FirstOrDefault(tab => tab.Id == page.TabId)).OfType<TabState>()
                .Where(tab => tab.Placement == location && tab.FolderId != Id).Select(tab => tab.Id).Distinct().ToList();
            var leaving = space.Tabs.Where(tab => tab.FolderId == Id && pages.All.Any(page => page.TabId == tab.Id
                    && page.Engine.Kind == Engine && page.Phase == PagePhase.Live && page.WindowId == report.WindowId
                    && !report.PageIds.Contains(page.Id)))
                .Select(tab => tab.Id).ToList();
            try {
                workspace.Handle(new ShowTabGroup(workspaceId, SpaceId, Id, titled ? report.Title : null,
                    colored ? report.Color.Color : null, collapsed ? report.IsCollapsed : null, joining, leaving),
                    pages.Clock.Now, pages.Ids, pages);
            } catch (Rejected) {
                // The Space holds as many folders as it may.
            }
            if (Editable(workspace)?.Folders.FirstOrDefault(folder => folder.Id == Id) is { } shown)
                (showsFolder, folderTitle, folderColor, seesFolder) = (true, shown.Title, shown.Color, true);
        }
        if (titled) wantedTitle = report.Title;
        if (colored) wantedColor = report.Color;
        (heldPageIds, heldTitle, heldColor, heldCollapsed) = (report.PageIds, report.Title, report.Color, report.IsCollapsed);
        var filed = FolderTabs(pages);
        outside = reported.Where(page => page.TabId is not { } tabId || !filed.Contains(tabId)).Select(page => page.Id).ToHashSet();
    }

    /// Asks the engine for what the folder shows now, when that differs from
    /// what the group holds: the title or color the person gave the folder,
    /// whether it is collapsed, and the live pages of its tabs, with the
    /// grouped pages it does not hold. A folder that lost its last tab goes,
    /// as a group does, and the group keeps only the pages outside it; a
    /// folder the person deleted takes every page out of the group. Answers
    /// whether the group is still followed.
    public bool Reconcile(Pages pages, Action<Engine, EngineCommand> issue) {
        if (!Located(pages)) return false;
        if (WorkspaceId is not { } workspaceId) return true;
        if (pages.Device.Attached(workspaceId) is not { } workspace) {
            // The persistent session's group waits for it to be attached again.
            Detach();
            return Persists;
        }
        if (workspace.Current.Spaces.FirstOrDefault(space => space.Id == SpaceId) is not { } space || workspace.IsDeleting(SpaceId))
            return false;
        if (workspace.IsLocked(space)) return true;
        var live = Live(pages);
        var kept = outside.Where(live.Contains).ToList();
        var folder = space.Folders.FirstOrDefault(candidate => candidate.Id == Id);
        if (folder is null) {
            if (!showsFolder) return kept.Count > 0;
            Ask(pages, issue, live, heldCollapsed, []);
            return false;
        }
        var tabs = space.Tabs.Where(tab => tab.FolderId == Id).ToList();
        if (tabs.Count == 0) {
            try {
                workspace.Handle(new DeleteFolder(workspaceId, SpaceId, Id), pages.Clock.Now, pages.Ids, pages);
            } catch (Rejected) {
                // The Space was locked or is being deleted meanwhile.
                return true;
            }
            showsFolder = false;
            Ask(pages, issue, live, heldCollapsed, kept);
            return kept.Count > 0;
        }
        if (seesFolder && folder.Title != folderTitle) wantedTitle = folder.Title;
        if (seesFolder && folder.Color != folderColor) wantedColor = TabGroupColor.Nearest(folder.DisplayColor);
        (folderTitle, folderColor, seesFolder) = (folder.Title, folder.Color, true);
        var held = tabs.SelectMany(tab => pages.All.Where(page => page.TabId == tab.Id && live.Contains(page.Id)))
            .Select(page => page.Id).ToList();
        Ask(pages, issue, live, folder.IsCollapsed, [.. held, .. kept.Where(page => !held.Contains(page))]);
        return true;
    }

    /// Issues `GroupPages` when the group should differ from what it holds,
    /// counting only its pages that are still live. A group with no live page
    /// asked for and none held has nothing to change.
    private void Ask(Pages pages, Action<Engine, EngineCommand> issue, HashSet<Guid> live, bool collapsed, IReadOnlyList<Guid> asking) {
        var holding = heldPageIds.Where(live.Contains).ToHashSet();
        if (asking.Count == 0 && holding.Count == 0 || pages.Engines.Registered(Engine) is not { } engine) return;
        if (wantedTitle == heldTitle && wantedColor == heldColor && collapsed == heldCollapsed && holding.SetEquals(asking)) return;
        (heldPageIds, heldTitle, heldColor, heldCollapsed) = (asking, wantedTitle, wantedColor, collapsed);
        issue(engine, new GroupPages(Id, wantedTitle, wantedColor, collapsed, asking));
    }

    /// The pages went with the workspace that hosted them, and the engine's
    /// group with them.
    public void Detach() {
        (WorkspaceId, heldPageIds, outside) = (null, [], new HashSet<Guid>());
    }

    #endregion

    #region Actions - Storage

    /// What the device store keeps of a group of the persistent session whose
    /// folder shows it, or null for a group it does not keep.
    public TabGroupRecord? Record() => Persists && showsFolder ? new(Id, SpaceId, Engine, wantedTitle, wantedColor) : null;

    #endregion

    #region Mutators

    /// Finds the workspace a group the device store kept belongs to: the
    /// persistent session, once attached, when it still holds the Space.
    /// Answers false for a group no workspace can show again.
    private bool Located(Pages pages) {
        if (WorkspaceId is not null) return true;
        if (!Persists) return false;
        if (pages.Device.Persistent() is not { } persistent) return true;
        if (!persistent.Authority.Current.Spaces.Any(space => space.Id == SpaceId)) return false;
        WorkspaceId = persistent.WorkspaceId;
        return true;
    }

    /// The Space the group's folder lives in, while this process may edit it.
    private SpaceState? Editable(NativeSessionAuthority workspace) =>
        workspace.Current.Spaces.FirstOrDefault(space => space.Id == SpaceId) is { } space && !workspace.IsDeleting(SpaceId)
            && !workspace.IsLocked(space)
            ? space : null;

    /// The tabs the group's folder holds now.
    private HashSet<Guid> FolderTabs(Pages pages) =>
        WorkspaceId is { } workspaceId
            && pages.Device.Attached(workspaceId)?.Current.Spaces.FirstOrDefault(space => space.Id == SpaceId) is { } space
            ? [.. space.Tabs.Where(tab => tab.FolderId == Id).Select(tab => tab.Id)]
            : [];

    /// The pages of the group's engine that are live there now.
    private HashSet<Guid> Live(Pages pages) =>
        [.. pages.All.Where(page => page.Engine.Kind == Engine && page.Phase == PagePhase.Live).Select(page => page.Id)];

    #endregion
}
