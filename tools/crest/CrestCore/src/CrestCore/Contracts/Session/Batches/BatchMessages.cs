namespace CrestCore.Contracts;

#region Queries

/// A selection previewed in the Space it was made in. `Selection` is what the
/// actions on it take: its roots by kind, holding `Members` as the window saw
/// them. `Roots` are the picks no picked folder holds, in sidebar order;
/// `Members` every tab the selection holds, in sidebar order; `FolderIds` the
/// picked folders and every folder inside them, in sidebar order.
public sealed record SelectedTabs(TabSelection Selection, IReadOnlyList<SelectedRoot> Roots, IReadOnlyList<SelectedTab> Members,
    IReadOnlyList<Guid> FolderIds);

/// A pick no picked folder holds: a tab, or a folder with everything in it.
public sealed record SelectedRoot(Guid Id, SidebarRowKind Kind);

/// A tab a selection holds, with where it lives.
public sealed record SelectedTab(Guid Id, TabPlacement Placement, Guid? FolderId, Guid? SplitGroupId);

#endregion

#region Rejections

/// The tabs would move to the Space `SpaceId`, which already holds them.
public sealed record AlreadyInSpace(Guid SpaceId) : Rejection;

/// The tab is in a split, and a split stays in its Space.
public sealed record CannotMoveSplitAcrossSpaces(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Split View groups stay in their Space. Separate the split before moving it to another Space.";

    #endregion
}

/// The tab is saved or pinned, and only open tabs are archived together.
public sealed record CurrentTabsOnly(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message =>
        "Archive applies to current tabs. Use Unload Pages to close saved or pinned pages, or Delete Tabs to remove their saved entries.";

    #endregion
}

/// The selection holds some members of the split `GroupId` and not the rest.
public sealed record IncompleteSplit(Guid GroupId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "The split changed. Select the whole group again.";

    #endregion
}

/// The selection is not what the window saw: the window no longer shows its
/// Space, or a selected tab or folder is gone, or its folders hold other tabs.
public sealed record SelectionChanged : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "The selected items changed. Select them again before continuing.";

    #endregion
}

/// The selection holds folders, which only filing and keeping pages loaded act on.
public sealed record SelectionHoldsFolders : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message =>
        "Move selected folders into saved or current tabs, or another folder. Use a folder’s own menu for other folder actions.";

    #endregion
}

/// The split would hold one tab, and a split holds two to `Limit` tabs.
public sealed record SplitNeedsTwoTabs(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "Split View needs 2 to %lld tabs. Select fewer tabs or use a smaller split.";

    #endregion
}

#endregion

#region Models

/// The tabs and folders a person selected together in a window's sidebar.
/// `TabIds` and `FolderIds` name what they picked; a tab or folder inside a
/// picked folder goes with that folder. `MemberTabIds` are the tabs the window
/// saw the selection hold when the person acted: each picked tab and every tab
/// inside a picked folder. The core refuses a selection that no longer holds
/// exactly those tabs, and acts on it in the order the Space's sidebar lists
/// it, whatever order the lists name it in.
public sealed record TabSelection(IReadOnlyList<Guid> TabIds, IReadOnlyList<Guid> FolderIds, IReadOnlyList<Guid> MemberTabIds);

#endregion
