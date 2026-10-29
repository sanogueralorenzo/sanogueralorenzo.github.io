namespace CrestCore.Contracts;

#region Queries

/// Whether returning a tab to its saved address would take it or its page
/// somewhere else.
public sealed record SavedAddressReturn(bool ChangesPage);

/// What a page surface shows.
public sealed record PagePresented(PagePresentation Presentation);

/// The entries a page can go back and forward to, nearest first.
public sealed record PageHistoryList(IReadOnlyList<PageHistoryEntry> Back, IReadOnlyList<PageHistoryEntry> Forward);

/// A page's back and forward history as its tab's archive keeps it, opaque
/// to the platform, or null for none.
public sealed record PageHistoryArchive(byte[]? Archive);

#endregion

#region Changes

public sealed record NavigationRecorded(Guid PageId, Guid WorkspaceId, Guid SpaceId, Guid? TabId, string Url) : Change;

/// The core adopted a page its engine opened by itself as the page `PageId`
/// names, owned by the tab `TabId` it opened in `SpaceId` of the workspace
/// `WorkspaceId`. The window `WindowId` names hosts the page, and shows the
/// tab when `Shows`.
public sealed record OfferedPageAdopted(Guid PageId, Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, bool Shows)
    : Change;


/// A page moved to another owner, or its engine created, failed or closed it.
public sealed record PageChanged(PageState Page) : Change;

[Observed]
public sealed record PageState(Guid Id, Guid WorkspaceId, Guid SpaceId, Guid? TabId, PagePhase Phase,
    PageLiveState Live);

/// A page opened, and its engine is creating it.
public sealed record PageOpened(PageState Page) : Change;

/// Its owner released a page, which is gone.
public sealed record PageRemoved(Guid PageId) : Change;

/// The core unloaded a page to give memory back. The tab keeps its place, and
/// its next page restores what this one showed. The page is gone, as
/// `PageRemoved` also says.
public sealed record PageUnloaded(Guid PageId, Guid WorkspaceId, Guid TabId) : Change;

public sealed record TransientPageClosed(Guid PageId, Guid WorkspaceId) : Change;

#endregion

#region Rejections - Pages

/// A page with this identity is already open.
public sealed record DuplicatePage(Guid PageId) : Rejection;

/// The page's engine holds no page to load into: it could not create it, or
/// the page closed.
public sealed record PageNotLoadable(Guid PageId) : Rejection;

/// The Space keeps another profile than the one the page's engine page lives
/// in, so the page cannot move there.
public sealed record PageProfileMismatch(Guid PageId, Guid SpaceId) : Rejection;

/// The page cannot load the link staged in `SourcePageId`: it lives on another
/// engine or profile, or its engine already holds its page.
public sealed record StagedLinkElsewhere(Guid PageId, Guid SourcePageId) : Rejection;

/// The tab already owns `PageId` in this window; a window hosts one page for a
/// tab at a time. Windows that share their pages reuse that one, and a window
/// with pages of its own, as each iPad scene has, opens its own.
public sealed record TabAlreadyHasPage(Guid TabId, Guid PageId) : Rejection;

/// The intent names a page that is not open.
public sealed record UnknownPage(Guid PageId) : Rejection;

#endregion

#region Rejections - Spaces

/// The Space is being deleted, so nothing new may live in its profile.
public sealed record SpaceBeingDeleted(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That Space is being deleted.";

    #endregion
}

/// The workspace holds no Space with this identity.
public sealed record UnknownSpace(Guid SpaceId) : Rejection;

#endregion

#region Models

/// Why a page's navigation to `Url` failed. `Error` names the problem the same
/// way whichever engine saw it, and is what behavior that differs by failure
/// reads. `ReplacedDocument` says the failure took the place of the document
/// the page showed, as an engine's committed error page does; otherwise the
/// page still shows that document behind the failure, and leaving the failure
/// returns to it. `Domain` and `Code` are the engine's own error, which the
/// failure page shows as technical details and nothing branches on.
public sealed record PageFailure(NavigationError Error, string? Url, bool ReplacedDocument, string Domain, long Code);

/// What media a page runs now: audio or video playing, the camera or the
/// microphone capturing, or a video in Picture in Picture.
[Flags]
public enum PageMediaActivity {
    None = 0,
    Playing = 1 << 0,
    Capturing = 1 << 1,
    PictureInPicture = 1 << 2
}

#endregion
