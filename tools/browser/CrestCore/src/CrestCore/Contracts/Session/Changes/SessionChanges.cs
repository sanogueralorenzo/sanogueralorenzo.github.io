namespace CrestCore.Contracts;

#region Workspaces

/// <summary>A workspace's own members now read as these: the Space a launch opens,
/// whether the session is still the disposable first-install seed, and the Space
/// deletions under way on this device.</summary>
public sealed record WorkspaceChanged(Guid WorkspaceId, Guid? DefaultSpaceId, bool IsDisposableSeed,
    IReadOnlyList<SpaceDeletionState> SpaceDeletions) : Change;

/// <summary>A workspace left this device, and its windows with it.</summary>
public sealed record WorkspaceClosed(Guid WorkspaceId) : Change;

/// <summary>A workspace joined this device: its kind and the whole session it holds.
/// Every later change to that session names <see cref="WorkspaceId"/>.</summary>
public sealed record WorkspaceOpened(Guid WorkspaceId, WorkspaceKind Kind, SessionState Session) : Change;

#endregion

#region Spaces

/// This process's access to one Space's profile: whether it holds the grant
/// that unlocking gives, and whether a request to unlock it is waiting on the
/// device owner. A Space that asks for authentication shows only while its
/// profile is unlocked; one that opens freely always shows.
public sealed record SpaceLockChanged(Guid SpaceId, Guid ProfileId, bool IsUnlocked, bool IsAuthenticating) : Change;

/// <summary>A Space's settings now read as <see cref="Settings"/>.</summary>
public sealed record SpaceSettingsChanged(Guid WorkspaceId, Guid SpaceId, SpaceSettings Settings) : Change;

#endregion

#region Tabs

/// <summary>A command made <see cref="CopyTabId"/> as a copy of <see cref="SourceTabId"/>,
/// so the copy shows the image the platform keeps for its source.</summary>
public sealed record TabCopied(Guid WorkspaceId, Guid SourceTabId, Guid CopyTabId) : Change;

/// <summary>The core decided which image a tab shows. When <see cref="Adopts"/> it
/// wears the image <see cref="PageId"/> reported, or with no page the one the
/// issuer of its command offered; otherwise it wears none. The image bytes stay
/// with the platform.</summary>
public sealed record TabFaviconAssigned(Guid WorkspaceId, Guid TabId, bool Adopts, Guid? PageId) : Change;

/// The saved or pinned tab `TabId` put its page away, as window `WindowId`
/// asked. The platform that hosts the tab's page for that window lets it go,
/// keeping what brings it back when `KeepsState`; otherwise the tab returned
/// to its saved address and nothing of its page is kept.
public sealed record TabPagePutAway(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, bool KeepsState) : Change;

/// An import placed these tabs, open or archived, each from a tab of the Spaces
/// it brought, so each wears the image its importer holds for the tab it came
/// from.
public sealed record TabsImported(Guid WorkspaceId, IReadOnlyList<ImportedTab> Tabs) : Change;

/// A Quick Window's or Peek's page, `PageId`, became the tab `TabId`. When
/// `AdoptsPage`, the tab takes the live page, which the platform moves to the
/// tab's window; otherwise the page goes and the tab opens its own.
public sealed record TransientPagePromoted(Guid WorkspaceId, Guid PageId, Guid TabId, bool AdoptsPage) : Change;

#endregion

#region Organization

/// <summary>
/// A Space's sidebar lists changed. Each list in <see cref="Lists"/> replaces the list of
/// its section's top level, or of its folder's inside, and the lists of
/// <see cref="RemovedFolderIds"/> are gone with their folders. Every other list is as it
/// was. A Space that arrives whole carries its whole outline instead.
/// </summary>
public sealed record SidebarChanged(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<SidebarList> Lists,
    IReadOnlyList<Guid> RemovedFolderIds) : Change;

/// <summary>A Space's split metadata now reads as <see cref="Groups"/>.</summary>
public sealed record SplitGroupsChanged(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<SplitGroupState> Groups) : Change;

#endregion

#region Preferences

/// <summary>A workspace's app-wide preferences now read as <see cref="Preferences"/>,
/// or as none before they are imported.</summary>
public sealed record AppPreferencesChanged(Guid WorkspaceId, AppPreferences? Preferences) : Change;

#endregion
