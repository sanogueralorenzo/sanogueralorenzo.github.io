namespace CrestCore.Contracts;

#region Queries

/// Where a lift may drop. `Refusal` is the rule that refuses the lift itself,
/// such as `SelectionChanged` or `PinnedTabsDragAlone`, which leaves every list
/// empty. Otherwise `Lists` holds every list of the Space's sidebar, sections
/// first and then each folder's inside; `SpaceIds` every other Space the window
/// may show; `Split` the cards the window shows, with the rule that refuses
/// joining them, or null when it shows no tab; and `FolderAroundTabIds` the
/// open tabs a new folder may be made around, in sidebar order. Whether a drop
/// lands in a list or on a Space is asked of that drop, once the lift reaches
/// it, so a lift pays only for the targets it visits.
public sealed record DropTargetList(Rejection? Refusal, IReadOnlyList<ListDropTarget> Lists, IReadOnlyList<Guid> SpaceIds,
    SplitDropTarget? Split, IReadOnlyList<Guid> FolderAroundTabIds);

/// One list of a Space's sidebar a lift may drop into: the inside of
/// `FolderId`, or the top level of `Section`. Whether a drop lands there is
/// asked of the drop itself, as `CanSend` asks any intent.
public sealed record ListDropTarget(TabPlacement Section, Guid? FolderId);

/// The cards a window shows, the split of `TabId`, the tab it shows, and the
/// rule that refuses a lift joining them, or null when it may.
public sealed record SplitDropTarget(Guid TabId, Rejection? Refusal);

#endregion

#region Rejections

/// The lift holds pinned tabs with saved or open tabs or folders, which move
/// apart.
public sealed record PinnedTabsDragAlone : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Pinned tabs cannot join a drag with saved or current tabs. Start the drag again.";

    #endregion
}

/// Several pinned tabs would drop on another Space or the cards a window shows,
/// where pinned tabs move one at a time.
public sealed record PinnedTabsStayPut : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Move selected pinned tabs within their pinned area or into saved or current tabs.";

    #endregion
}

/// Several tabs, or a folder, would drop among the pinned tabs, which take tabs
/// one at a time.
public sealed record PinsOneTabAtATime : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Drag one tab at a time to pin it.";

    #endregion
}

#endregion
