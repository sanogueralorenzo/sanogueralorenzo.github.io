namespace CrestCore.Contracts;

#region Queries

/// Whether a dragged tab may leave its window, and when it may not, why.
public sealed record TearOffPermission(bool Allowed, TearOffRefusal? Reason);

/// Why a dragged tab may not leave its window.
public enum TearOffRefusal {
    /// The window no longer shows the Space the drag started in, with the
    /// profile it had, or the Space is being deleted.
    SpaceChanged,
    /// The Space is locked.
    SpaceLocked,
    /// The Space no longer holds the tab.
    TabGone,
    /// The drag carries more than the one tab.
    SeveralTabs
}

/// The index of a draft Space's fallback tab among the placements asked
/// about, or null for a Space without tabs.
public sealed record FallbackTabIndex(int? Index);

/// What a window's person switches between in the Space it shows: up to five
/// items, the one on screen first, then the rest most recent first. Empty
/// when the window shows no tab there.
public sealed record RecentTabList(IReadOnlyList<RecentTabItem> Items);

/// One thing to switch to: a tab, or the tabs of a split, which are one item.
/// `TabIds` are its tabs in the order they show side by side, and
/// `FocusedTabId` is the one to show, the one of a split used last.
public sealed record RecentTabItem(IReadOnlyList<Guid> TabIds, Guid FocusedTabId);

/// The tab "Split With Next Tab" would add, or null when it would add none.
public sealed record SplitJoinCandidateTab(Guid? TabId);

/// The tabs a swipe reaches back and on from the tab a window shows, each null
/// past that end.
public sealed record SwipeNeighborTabs(Guid? PreviousTabId, Guid? NextTabId);

/// What the Dock icon's menu shows: its window commands, then the Spaces a
/// window can show, in order. `WindowId` is the window a chosen Space shows
/// in and the commands act from, the frontmost over the persistent session,
/// or null when none is open, when a chosen Space opens a window on itself.
public sealed record DockMenuContent(IReadOnlyList<DockMenuCommand> Commands, IReadOnlyList<DockMenuSpace> Spaces, Guid? WindowId);

/// The windows a launch opens, back to front, each a saved window's identity:
/// the frontmost, `StartupWindowId`, takes the startup choice. `Setup` is the
/// setup that opens in front of them, and holds them back until it finishes,
/// or null when none does.
public sealed record LaunchWindowPlan(IReadOnlyList<Guid> WindowIds, Guid StartupWindowId, SetupEntry? Setup);

/// The window that comes to the person: an open one, or with `OpensWindow`, a
/// saved window's identity to open.
public sealed record ReopenedWindow(Guid WindowId, bool OpensWindow);

/// The window an engine-created browser window's tabs join and the Space they
/// belong to: an open window, or with `OpensWindow`, a new one to open. Both
/// are null when the tabs are declined.
public sealed record EngineWindowPlace(Guid? WindowId, Guid? SpaceId, bool OpensWindow);

/// One Space in the Dock icon's menu, drawn as the Space switcher draws it:
/// its name, symbol, accent and the look it wears, which says whether its
/// icon is its crest or its symbol. `IsShown` checks the Space the frontmost
/// window shows. `IsLocked` says this process holds no grant for it now, so
/// choosing it shows it locked until the person unlocks it there.
public sealed record DockMenuSpace(Guid SpaceId, Guid ProfileId, string Name, string Symbol, SpaceAccent Accent,
    SpaceBranding Look, bool IsShown, bool IsLocked);

#endregion

#region Changes

/// A window comes to the front, with the app: it shows the tab whose page the
/// person returned to from Picture in Picture.
public sealed record WindowBroughtForward(Guid WindowId) : Change;

/// An open window shows something else: it opened, a person chose what it
/// shows, or the session changed under it and the core repaired it.
public sealed record WindowChanged(WindowState Window) : Change;

/// A window is no longer open.
public sealed record WindowClosed(Guid WindowId) : Change;

/// The device store holds the window records an installed release kept.
/// `Layouts` are the sidebar values those records also carried, which the
/// platform keeps as its own; the core keeps none of them.
public sealed record WindowRecordsAdopted(IReadOnlyList<WindowLayout> Layouts) : Change;

/// The sidebar a window kept: its width and whether it was presented, each
/// absent when the window never set it.
public sealed record WindowLayout(Guid WindowId, double? SidebarWidth, bool? SidebarIsPresented);

#endregion

#region Rejections

/// The shares cannot describe a split's columns: none, more than a split may
/// hold, or one that is not a finite share greater than zero and at most the
/// whole width.
public sealed record InvalidSplitColumnShares : Rejection;

/// The Space is locked, and this process holds no grant to read or change it.
public sealed record SpaceLocked(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "The Space is locked or no longer active. Unlock it and select the tabs again.";

    #endregion
}

/// The intent names a workspace that is not attached to this device.
public sealed record UnknownWorkspace(Guid WorkspaceId) : Rejection;

/// Only a window over the persistent session may be saved; this workspace
/// lives in memory.
public sealed record UnsavedWorkspace(Guid WorkspaceId) : Rejection;

/// The intent names a window that is not open.
public sealed record WindowNotOpen(Guid WindowId) : Rejection;

#endregion

#region Models

/// The tab a window shows in one Space, or none.
public sealed record ShownTab(Guid SpaceId, Guid? TabId);

#endregion
