namespace CrestCore.Contracts;

/// What an engine binding tells the platform directly about one of its pages:
/// presentation that no browser rule reads, such as how many matches a find
/// counted, and the results of requests that finish later. The core never
/// sees these.
public abstract record EnginePresentation;

/// What the binding tells the platform about one of its pages, which its
/// `PageId` names, so the page it is about hears it.
public abstract record EnginePagePresentation(Guid PageId) : EnginePresentation;

#region Pages

/// The page's latest find counted `Matches` matches and selected the
/// `ActiveMatch`th, counted from 1; none found when `Matches` is 0. An engine
/// that finds a match but cannot count them leaves `Matches` null.
public sealed record FindFinished(Guid PageId, int? Matches, int ActiveMatch) : EnginePagePresentation(PageId);

/// The link under the pointer in the page, or none when the pointer left it.
public sealed record LinkHovered(Guid PageId, string? Url) : EnginePagePresentation(PageId);

/// The capture `CaptureId` asked for, as a PNG, or nothing when the page's
/// view showed nothing to capture.
public sealed record PageCaptured(Guid PageId, Guid CaptureId, byte[]? Png) : EnginePagePresentation(PageId);

/// The export `ExportId` asked for: its document, or why there is none.
public sealed record PageExported(Guid PageId, Guid ExportId, byte[]? Document, PageExportFailure? Failure) : EnginePagePresentation(PageId);

/// The person typed, clicked or scrolled in the page. Presented at most once a
/// second, for timers that close pages left idle.
public sealed record PageInteracted(Guid PageId) : EnginePagePresentation(PageId);

/// The page started or stopped loading.
public sealed record PageLoadingChanged(Guid PageId, bool IsLoading) : EnginePagePresentation(PageId);

/// The page now shows the document at `Url`, a new one or a move within the
/// same one, and is still loading it when `IsLoading`.
public sealed record PageNavigationCommitted(Guid PageId, string Url, bool IsLoading) : EnginePagePresentation(PageId);

/// The page's navigation failed; the engine shows its own error page.
public sealed record PageNavigationFailed(Guid PageId) : EnginePagePresentation(PageId);

/// The page began loading a new document; what the platform keeps for the
/// document it shows now is about to go stale.
public sealed record PageNavigationStarted(Guid PageId) : EnginePagePresentation(PageId);

/// The process that drew the page stopped, so the page shows nothing until it
/// loads again.
public sealed record PageRendererGone(Guid PageId) : EnginePagePresentation(PageId);

/// The colour the page's document declared for its surroundings, or none.
public sealed record PageThemeChanged(Guid PageId, BrandColor? Color) : EnginePagePresentation(PageId);

/// The engine closed the page on its own authority, as an extension's
/// `chrome.tabs.remove` does. The core closes what owned it (see `PageClosed`).
public sealed record PageViewClosed(Guid PageId) : EnginePagePresentation(PageId);

/// The engine created the page, so its view can be shown.
public sealed record PageViewReady(Guid PageId) : EnginePagePresentation(PageId);

/// The engine could not create the page, so it has no view to show.
public sealed record PageViewUnavailable(Guid PageId) : EnginePagePresentation(PageId);

/// A link in the page asked to open in Peek, as the core decided (`Decision`),
/// and the engine kept the page where it was. `StagedLinkId` names the link the
/// engine staged for the Peek's first load, which keeps its referrer and
/// initiator; without one the Peek loads `Url` afresh. A Peek that does not
/// open discards the staged link.
public sealed record PeekRequested(Guid PageId, string Url, LinkNavigationDecision Decision, Guid? StagedLinkId)
    : EnginePagePresentation(PageId);

/// The engine blocked a pop-up the document at `PageUrl` opened.
public sealed record PopupBlocked(Guid PageId, string PageUrl) : EnginePagePresentation(PageId);

#endregion

#region Content

/// The page's content entered or left fullscreen. The page still owns its
/// fullscreen and leaves it on Escape.
public sealed record ContentFullscreenChanged(Guid PageId, bool Active) : EnginePagePresentation(PageId);

/// A Crest content script in `Frame` posted `Body`, as JSON, to `Handler`.
public sealed record ContentMessagePosted(Guid PageId, string Handler, string Body, ContentFrame Frame)
    : EnginePagePresentation(PageId);

/// A frame of a page's document: the identity `EvaluateContentScript` takes,
/// whether it is the main frame, and the origin of what it shows.
public sealed record ContentFrame(string Id, bool IsMainFrame, string Protocol, string Host, int Port);

/// What `EvaluateContentScript` answered, as JSON, or nothing when its
/// document went away first.
public sealed record ContentScriptEvaluated(Guid PageId, Guid EvaluationId, string? Json) : EnginePagePresentation(PageId);

#endregion

#region Agents

/// What `EvaluatePageScript` `EvaluationId` settled with: its value as JSON,
/// or the message of the error it threw, or neither when its document went
/// away first.
public sealed record PageScriptEvaluated(Guid PageId, Guid EvaluationId, string? Json, string? Error)
    : EnginePagePresentation(PageId);

/// Whether the engine delivered input `InputId` to the page, and whether the
/// page sees it as the person's own input rather than script events.
public sealed record PageInputDelivered(Guid PageId, Guid InputId, bool Delivered, bool Trusted)
    : EnginePagePresentation(PageId);

#endregion

#region Info Bars

/// The bar `InfoBarShown` presented is gone.
public sealed record InfoBarRemoved(Guid PageId, int InfoBarId) : EnginePagePresentation(PageId);

/// The engine asks the person something in a bar over the page: a message and
/// the labels of the buttons it has. The person's answer is `AnswerInfoBar`.
/// A `Minimizable` bar only reports something that lasts, such as a tab being
/// shared, so the person may hide it until they come back to the page.
public sealed record InfoBarShown(Guid PageId, int InfoBarId, string Message, string? AcceptLabel, string? CancelLabel,
    bool Closeable, bool Minimizable) : EnginePagePresentation(PageId);

#endregion

#region Notifications

/// A document in the page posted a notification. The platform shows it as
/// Crest's own when the core lets the page's Space show the site's
/// notifications and the system lets Crest show them, and answers with
/// `AnswerWebNotification` once the person clicks it or it will not show.
public sealed record WebNotificationPosted(Guid PageId, string NotificationId, SiteOrigin Origin, string Title, string Body,
    bool Silent) : EnginePagePresentation(PageId);

/// The page's document closed a notification `WebNotificationPosted`
/// presented, so the platform takes it down.
public sealed record WebNotificationClosed(Guid PageId, string NotificationId) : EnginePagePresentation(PageId);

/// A notification belonging to a profile independently of any open page.
public sealed record ProfileNotificationPosted(Guid ProfileId, string NotificationId, SiteOrigin Origin,
    ProfileNotificationSource Source, string Title, string Body, bool Silent) : EnginePresentation;

/// The engine withdrew a worker's or extension's notification.
public sealed record ProfileNotificationClosed(Guid ProfileId, string NotificationId) : EnginePresentation;

public enum ProfileNotificationSource { ServiceWorker, Extension }

#endregion

#region Extensions

/// The extensions of the profile `ProfileId` names changed: one was added,
/// removed, enabled or pinned, or an action's state or icon changed.
public sealed record ExtensionsChanged(Guid ProfileId) : EnginePresentation;

/// The engine asks for the extension's side panel beside the page: its
/// `chrome.sidePanel.open()` or `close()`, or an action click that toggles
/// the panel instead of opening a popup. A panel is a card beside the page,
/// so the engine never opens or closes one itself.
public sealed record SidePanelRequested(Guid PageId, string ExtensionId, SidePanelRequest Request)
    : EnginePagePresentation(PageId);

/// What the engine asks of an extension's side panel.
public enum SidePanelRequest {
    Open,
    Close,
    Toggle
}

/// The Chrome Web Store listing the page shows asked to install the extension
/// it is about. The engine checked the listing names `ExtensionId`.
public sealed record StoreInstallRequested(Guid PageId, string ExtensionId) : EnginePagePresentation(PageId);

/// The Chrome Web Store listing the page shows asked to remove the extension
/// it is about. The engine checked the listing names `ExtensionId`.
public sealed record StoreRemovalRequested(Guid PageId, string ExtensionId) : EnginePagePresentation(PageId);

#endregion

#region Media

/// What a media session can be asked to do.
public enum MediaSessionAction {
    Play,
    Pause,
    PreviousTrack,
    NextTrack
}

/// The page's media session as Crest shows it for `Document`: what plays, how,
/// and what it can be asked to do. `Sequence` counts up with each change so a
/// late one never replaces a newer one. `Artwork` is the image the page gave
/// for what plays, as a PNG in its own shape, or none until the engine fetched
/// it.
public sealed record MediaSessionChanged(Guid PageId, string Document, long Sequence, string Location, bool Active,
    string? Title, string? Artist, string? Album, byte[]? Artwork, MediaPlayback Playback, bool Audible, bool Muted,
    IReadOnlyList<MediaSessionAction> Actions) : EnginePagePresentation(PageId);

/// How loud the sound the page plays is now in each of `Bands` frequency bands,
/// lowest first, from 0 for silence to 255 at its loudest, a few times a second
/// while the platform observes it with `ObserveAudioSpectrum`.
public sealed record AudioSpectrumChanged(Guid PageId, byte[] Bands) : EnginePagePresentation(PageId);

/// A document in the page asked to capture the screen in a way that needs the
/// system's Screen Recording access, which Crest does not have. The engine
/// asked the system for it once and refused the request; the platform says
/// where the person can allow it. Sharing through the system's own picker
/// never needs that access.
public sealed record ScreenCaptureAccessMissing(Guid PageId) : EnginePagePresentation(PageId);

/// A document in the page asked to share the screen, and the core let its
/// site ask. Before the system's picker, which offers windows and displays,
/// the platform asks the person whether to share one of `Tabs` instead, and
/// answers with `ChooseShareSource` and `ShareId`. `Site` names the document
/// that asks, as the person reads it. `Audio` says whether it asked for
/// audio too, which a shared tab can carry.
public sealed record ShareSourcesOffered(Guid PageId, Guid ShareId, string Site, IReadOnlyList<ShareableTab> Tabs, bool Audio)
    : EnginePagePresentation(PageId);

/// The request `ShareSourcesOffered` asked about ended before the person
/// chose, so the platform takes its question down.
public sealed record ShareSourcesWithdrawn(Guid PageId, Guid ShareId) : EnginePagePresentation(PageId);

/// A page the person can share as a tab: its identity, its title, its
/// address and its icon as a PNG, when it has them.
public sealed record ShareableTab(Guid PageId, string Title, string? Url, byte[]? Icon);

/// The page's part in tab sharing changed: `Shared` while another page shares
/// it as a tab, and `Sharing` while it shares another tab, so its tab can show
/// it and offer to stop.
public sealed record TabSharingChanged(Guid PageId, bool Shared, bool Sharing) : EnginePagePresentation(PageId);

/// Whether a media session plays.
public enum MediaPlayback {
    /// It has nothing to play.
    None,

    Playing,
    Paused
}

#endregion

#region Inspectors

/// The inspector on the page is going away, whichever way it was closed.
public sealed record InspectorClosed(Guid PageId) : EnginePagePresentation(PageId);

/// The docked inspector on the page appeared, moved to another side, changed
/// size or went away, so the page's card lays out again.
public sealed record InspectorLayoutChanged(Guid PageId) : EnginePagePresentation(PageId);

#endregion

#region Profiles

/// Whether the profile `PrepareProfile` asked for is ready.
public sealed record ProfilePrepared(Guid PreparationId, bool Ready) : EnginePresentation;

/// The engine let go of the profile `ProfileId` names: its pages and windows
/// closed and its extensions are gone.
public sealed record ProfileReleased(Guid ProfileId) : EnginePresentation;

#endregion
