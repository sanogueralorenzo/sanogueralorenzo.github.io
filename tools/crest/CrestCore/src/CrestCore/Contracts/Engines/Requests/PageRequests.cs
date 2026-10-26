namespace CrestCore.Contracts;

/// What the platform asks a page's engine binding directly, as `EnginePage`
/// does: view work such as going back, finding text or capturing the page,
/// which changes no browser state. The binding answers with a `TAnswer` at
/// once; work that finishes later answers with an `EnginePresentation`. The
/// core never sees these; they share the engine contract so every binding
/// answers the same requests.
public abstract record PageRequest<TAnswer>;

#region Pages

/// The person's answer to the bar `InfoBarShown` presented.
public sealed record AnswerInfoBar(Guid PageId, int InfoBarId, InfoBarAnswer Answer) : PageRequest<bool>;

/// How the person answered an engine's bar.
public enum InfoBarAnswer {
    /// Its accept button.
    Accept,

    /// Its cancel button.
    Cancel,

    /// Its close button, which answers neither.
    Dismiss
}

/// Captures what the page's view shows, all of it or `Area` in view points,
/// scaled to `Width` points wide or at its own size when `Width` is 0, and
/// answers `PageCaptured` with `CaptureId`. False when the page shows nothing
/// to capture.
public sealed record CapturePage(Guid PageId, Guid CaptureId, PageArea? Area, double Width) : PageRequest<bool>;

/// A rectangle of a page's view, in points from its top left.
public sealed record PageArea(double X, double Y, double Width, double Height);

/// Exports the page's document as `Format`, a full-page image `Width` points
/// wide or at its own width when `Width` is 0, and answers `PageExported` with
/// `ExportId`. The export ends when the page navigates, closes or loses its
/// renderer.
public sealed record ExportPage(Guid PageId, Guid ExportId, PageExportFormat Format, double Width) : PageRequest<bool>;

/// What an export of a page's document makes.
public enum PageExportFormat {
    /// A PDF of the document as it prints.
    Pdf,

    /// A PNG of the whole document.
    Png,

    /// An MHTML archive of the document and its resources, as Chromium keeps
    /// one.
    Mhtml,

    /// A web archive of the document and its resources, as WebKit keeps one.
    WebArchive
}

/// Finds the next match of `Query` in the page, wrapping at its end, and
/// answers `FindFinished` once the engine has counted. An empty query clears
/// the page's matches. False when the page cannot search.
public sealed record FindInPage(Guid PageId, string Query, bool Backwards, bool CaseSensitive) : PageRequest<bool>;

/// The page's view left the screen.
public sealed record HidePage(Guid PageId) : PageRequest<bool>;

/// Moves the page into the engine's part of the window `WindowId` names,
/// keeping its history, renderer and extension identity, before the window
/// shows it.
public sealed record MovePageToWindow(Guid PageId, Guid WindowId) : PageRequest<bool>;

/// The certificates the page's visible entry was verified with.
public sealed record PageCertificates(Guid PageId) : PageRequest<CertificateChain>;

/// A verified connection's certificates as DER, the leaf first; none when the
/// page was not loaded over a verified TLS connection.
public sealed record CertificateChain(IReadOnlyList<byte[]> Certificates);

/// The icon the engine found for the document the page shows, which the
/// page's tab takes once the core assigns it.
public sealed record PageIcon(Guid PageId) : PageRequest<PageIconImage>;

/// The image of a page's icon as its engine found it, or nothing.
public sealed record PageIconImage(byte[]? Image);

/// Whether an inspector is open on the page, docked or in a window of its own.
public sealed record PageInspected(Guid PageId) : PageRequest<bool>;

/// Loads the engine profile of the Space profile `ProfileId` names, so its
/// extensions can be listed before anything opens in it, and presents
/// `ProfilePrepared` with `PreparationId`. False when it cannot start.
public sealed record PrepareProfile(Guid ProfileId, Guid PreparationId) : PageRequest<bool>;

/// Fetches the page's icon again rather than keep the one the engine has.
public sealed record RefreshPageIcon(Guid PageId) : PageRequest<bool>;

/// Reloads the page's document, fetching it again from its origin when
/// `BypassesCache`.
public sealed record ReloadPage(Guid PageId, bool BypassesCache) : PageRequest<bool>;

/// Allows or blocks `Permission` for the site the page shows, as Crest's record
/// decided, or clears the site's own setting so the engine's default applies.
public sealed record SetSitePermission(Guid PageId, SitePermission Permission, bool? Allowed) : PageRequest<bool>;

/// Opens the pop-ups the engine blocked in the page's document. False when it
/// blocked none.
public sealed record ShowBlockedPopups(Guid PageId) : PageRequest<bool>;

/// The page's view is on screen and takes focus.
public sealed record ShowPage(Guid PageId) : PageRequest<bool>;

/// Stops what the page is loading.
public sealed record StopLoading(Guid PageId) : PageRequest<bool>;

/// The platform shows the page from now on. False when the engine does not
/// know it. Otherwise the binding presents where the page stands, whether its
/// view is ready or could not be made, and what that view shows, since the
/// platform may come to a page after the engine created it.
public sealed record WatchPage(Guid PageId) : PageRequest<bool>;

/// Shows the page at `Factor` times its size, from 0.25 to 5. A page still
/// being created takes the factor once it exists.
public sealed record ZoomPage(Guid PageId, double Factor) : PageRequest<bool>;

#endregion

#region Extensions

/// Changes an installed extension in the profile `ProfileId` names. False when
/// the person may not change it.
public sealed record ChangeExtension(Guid ProfileId, string ExtensionId, ExtensionChange Change) : PageRequest<bool>;

/// What the person can change about an installed extension.
public enum ExtensionChange {
    Enable,
    Disable,
    Remove,
    Pin,
    Unpin
}

/// Which side panel, if any, the extension has for the page's own tab.
public sealed record HasSidePanel(Guid PageId, string ExtensionId) : PageRequest<SidePanelScope>;

/// Which side panel an extension has for a tab.
public enum SidePanelScope {
    /// None: the extension has no panel for the tab, or turned it off there.
    Unavailable,
    /// One the extension gave that tab alone, which stays with the tab.
    Tab,
    /// The extension's panel for every tab with none of its own (Chromium's
    /// global panel), which stays open as the person moves between such tabs.
    Window
}

/// The extensions installed in the profile `ProfileId` names, for Settings.
public sealed record InstalledExtensions(Guid ProfileId) : PageRequest<InstalledExtensionList>;

/// Installed extensions, as an engine lists them.
public sealed record InstalledExtensionList(IReadOnlyList<InstalledExtension> Extensions);

/// One installed extension: what it is, its icon as a PNG, whether it is
/// enabled, the permission warnings it carries, whether it came from the
/// Chrome Web Store, and its options page, if it has one.
public sealed record InstalledExtension(string Id, string Name, string Version, string Description, byte[]? Icon,
    bool Enabled, IReadOnlyList<string> Permissions, bool FromWebStore, string? OptionsUrl);

/// The extension actions the page's toolbar offers, with each one's state for
/// the page's own tab: its badge, its icon and whether it is pinned.
public sealed record PageExtensions(Guid PageId) : PageRequest<ExtensionActionList>;

/// Extension actions, as an engine lists them.
public sealed record ExtensionActionList(IReadOnlyList<ExtensionAction> Actions);

/// One extension's action: its name, badge text and icon as a PNG, whether it
/// is pinned, and whether it can run with no page to act on.
public sealed record ExtensionAction(string Id, string Name, string Badge, byte[]? Icon, bool Pinned, bool Enabled);

/// The extension actions pinned in the profile `ProfileId` names, which its
/// Space shows whether or not a page is open. A private profile offers only
/// the extensions allowed in private windows.
public sealed record PinnedExtensions(Guid ProfileId) : PageRequest<ExtensionActionList>;

/// The Chrome Web Store listing the page shows restates its install button
/// from the engine's own registry: the review its request began finished, or
/// never started.
public sealed record RefreshStoreListing(Guid PageId) : PageRequest<bool>;

#endregion

#region Media

/// The page's media session is the one Crest shows for `Document`, the
/// identity Crest issued for the document the page shows now.
public sealed record ActivateMediaSession(Guid PageId, string Document) : PageRequest<bool>;

/// Moves the video the page is playing, or last played before it left the
/// screen, into Picture in Picture. False when it has none to move or one is
/// already there.
public sealed record EnterPictureInPicture(Guid PageId) : PageRequest<bool>;

/// Mutes or unmutes the page while its media session is still `Document`'s.
public sealed record MuteMediaSession(Guid PageId, string Document, bool Muted) : PageRequest<bool>;

/// Starts or stops measuring the sound the page plays, band by band, which the
/// engine presents as `AudioSpectrumChanged` while it is observed. False when
/// the page is gone.
public sealed record ObserveAudioSpectrum(Guid PageId, bool Observed) : PageRequest<bool>;

/// What media the page runs at this moment.
public sealed record PageMedia(Guid PageId) : PageRequest<PageMediaState>;

/// What media a page runs, as its engine answers it.
public sealed record PageMediaState(PageMediaActivity Activity);

/// Runs `Action` in the page's media session while it is still `Document`'s.
public sealed record PerformMediaAction(Guid PageId, string Document, MediaSessionAction Action) : PageRequest<bool>;

/// Ends the page's live capture from `Permission`'s devices, after Crest
/// withdrew the grant that allowed it. False when the engine ends capture
/// itself once `SetSitePermission` blocks it.
public sealed record StopMediaCapture(Guid PageId, SitePermission Permission) : PageRequest<bool>;

/// The person's answer to `ShareSourcesOffered`. With `ShareSourceChoice.Tab`
/// the page shares the tab whose page is `TabPageId`, with its sound when
/// `Audio` says so. False when the request already ended, or the tab can no
/// longer be shared, which refuses the request.
public sealed record ChooseShareSource(Guid PageId, Guid ShareId, ShareSourceChoice Choice, Guid? TabPageId, bool Audio)
    : PageRequest<bool>;

/// Stops every tab sharing the page takes part in, as the shared tab or as
/// the page that shares one. False when it takes part in none.
public sealed record StopTabSharing(Guid PageId) : PageRequest<bool>;

/// What the person chose to share.
public enum ShareSourceChoice {
    /// Nothing: the request is refused.
    Cancel,

    /// The tab the answer names.
    Tab,

    /// A window or a display, which the system's picker asks for next.
    WindowOrScreen
}

#endregion

#region Notifications

/// What became of a notification `WebNotificationPosted` presented, which the
/// document that posted it hears. False when the page no longer has it.
public sealed record AnswerWebNotification(Guid PageId, string NotificationId, WebNotificationAnswer Answer)
    : PageRequest<bool>;

/// The platform's answer to a notification owned by a profile instead of a page.
public sealed record AnswerProfileNotification(Guid ProfileId, string NotificationId, WebNotificationAnswer Answer)
    : PageRequest<bool>;

/// What became of a notification a document posted.
public enum WebNotificationAnswer {
    /// The person clicked it, and its page came forward.
    Clicked,

    /// Crest did not show it: the page's Space does not let the site post
    /// notifications, or the system does not let Crest show them.
    Declined
}

#endregion

#region Scripts

/// Runs `Source` in Crest's own isolated world of every document the page
/// loads from now on, or of its main frame only. Its messages arrive as
/// `ContentMessagePosted`.
public sealed record AddContentScript(Guid PageId, string Source, bool MainFrameOnly) : PageRequest<bool>;

/// Runs `Source` once in Crest's isolated world of the frame `FrameId` names,
/// in the document it shows now, and presents `ContentScriptEvaluated` with
/// `EvaluationId`. False when the frame is gone.
public sealed record EvaluateContentScript(Guid PageId, Guid EvaluationId, string Source, string FrameId)
    : PageRequest<bool>;

#endregion

#region Inspectors

/// Closes the inspector on the page, docked or in a window of its own.
public sealed record CloseInspector(Guid PageId) : PageRequest<bool>;

/// Where the docked inspector and the page it inspects go in a card `Width` by
/// `Height` points: the inspector takes its area and the page is drawn over it
/// at its own. Measured from the card's top left.
public sealed record LayoutInspector(Guid PageId, double Width, double Height) : PageRequest<InspectorLayout>;

/// The areas of a card the docked inspector and its page take, or neither when
/// no inspector is docked. A page area with no size means the inspector
/// covers the page on purpose.
public sealed record InspectorLayout(PageArea? Inspector, PageArea? Page);

/// Opens the engine's inspector on the page, docked in the page's own card, on
/// `Panel` when the engine can choose where it starts.
public sealed record OpenInspector(Guid PageId, InspectorPanel? Panel) : PageRequest<bool>;

/// Where an inspector starts.
public enum InspectorPanel {
    Console,
    Elements,
    Network
}

#endregion

#region Interaction State

/// A page's navigation history in its engine's own format, or nothing before
/// the page's first commit.
public sealed record InteractionState(byte[]? State);

/// Restores navigation history `SaveInteractionState` saved, in place of the
/// page's first load of `ExpectedUrl`, which the history must show. A page
/// still being created restores once it exists. False when the history is
/// another page's or the page has already loaded.
public sealed record RestoreInteractionState(Guid PageId, byte[] State, string ExpectedUrl) : PageRequest<bool>;

/// The page's navigation history in the engine's own format, which
/// `RestoreInteractionState` brings back.
public sealed record SaveInteractionState(Guid PageId) : PageRequest<InteractionState>;

#endregion

#region Agents

/// Runs `Source`, the body of an async JavaScript function, in the main frame
/// of the page's document in `World`, and presents `PageScriptEvaluated` with
/// `EvaluationId` once it settles. False when the page has no document to run
/// it in.
public sealed record EvaluatePageScript(Guid PageId, Guid EvaluationId, string Source, PageScriptWorld World)
    : PageRequest<bool>;

/// Where a script an agent asked for runs: the agent world, which the page
/// and Crest's own content scripts never see, or the page's own world.
public enum PageScriptWorld {
    Agent,
    Page
}

/// Presses and releases `Button` `Count` times at `Point` in the page's view,
/// and presents `PageInputDelivered` with `InputId`.
public sealed record ClickPage(Guid PageId, Guid InputId, PagePoint Point, PointerButton Button, int Count,
    KeyModifiers Modifiers) : PageRequest<bool>;

/// Moves the pointer to `Point` in the page's view, and presents
/// `PageInputDelivered` with `InputId`.
public sealed record HoverPage(Guid PageId, Guid InputId, PagePoint Point) : PageRequest<bool>;

/// Scrolls `DeltaX` and `DeltaY` CSS pixels at `Point` in the page's view,
/// and presents `PageInputDelivered` with `InputId`.
public sealed record ScrollPage(Guid PageId, Guid InputId, PagePoint Point, double DeltaX, double DeltaY)
    : PageRequest<bool>;

/// Types `Text` into whatever the page has focused, and presents
/// `PageInputDelivered` with `InputId`.
public sealed record TypeInPage(Guid PageId, Guid InputId, string Text) : PageRequest<bool>;

/// Presses and releases `Key` with `Modifiers` held, and presents
/// `PageInputDelivered` with `InputId`.
public sealed record PressKeyInPage(Guid PageId, Guid InputId, PageKey Key, KeyModifiers Modifiers)
    : PageRequest<bool>;

/// A point in a page's viewport, in CSS pixels from its top left, as the
/// page's own scripts measure it.
public sealed record PagePoint(double X, double Y);

/// The pointer button input presses.
public enum PointerButton {
    Primary,
    Secondary,
    Middle
}

/// The modifier keys input holds down.
[Flags]
public enum KeyModifiers {
    None = 0,
    Shift = 1,
    Control = 2,
    Option = 4,
    Command = 8
}

/// A key as the DOM names it: `Key` is a KeyboardEvent key such as "Enter" or
/// "a", `Code` the physical key such as "KeyA", `KeyCode` the virtual key code
/// pages still read, and `Text` what the key types, if anything.
public sealed record PageKey(string Key, string Code, int KeyCode, string? Text);

/// Starts or stops keeping the page's console messages and network requests,
/// a bounded number of each, newest last. A page its engine is still making
/// starts when it is ready, before its first load. Stopping forgets what was
/// kept.
public sealed record ObservePageActivity(Guid PageId, bool Observing) : PageRequest<bool>;

/// The console messages the page kept after sequence `After`, oldest first.
public sealed record ReadPageConsole(Guid PageId, long After) : PageRequest<PageConsoleLog>;

/// The network requests the page kept after sequence `After`, oldest first.
public sealed record ReadPageNetwork(Guid PageId, long After) : PageRequest<PageNetworkLog>;

/// Console messages a page kept, and how many older ones it let go since it
/// started keeping them.
public sealed record PageConsoleLog(IReadOnlyList<PageConsoleMessage> Messages, long Dropped);

/// A message a page's scripts wrote to the console, or an error they threw.
public sealed record PageConsoleMessage(long Sequence, PageConsoleLevel Level, string Text, string? Source, int Line,
    DateTimeOffset At);

/// How severe a console message is.
public enum PageConsoleLevel {
    Debug,
    Log,
    Info,
    Warning,
    Error
}

/// Network requests a page kept, and how many older ones it let go since it
/// started keeping them.
public sealed record PageNetworkLog(IReadOnlyList<PageNetworkRequest> Requests, long Dropped);

/// A request a page made: what it asked for and, once answered, its status,
/// type, headers, size and how long it took, or why it failed. `Status` is 0
/// and `Duration` 0 while it runs. An engine that cannot see a field leaves it
/// empty.
public sealed record PageNetworkRequest(long Sequence, string Url, string Method, string ResourceType, int Status,
    string? MimeType, IReadOnlyList<PageHeader> RequestHeaders, IReadOnlyList<PageHeader> ResponseHeaders,
    DateTimeOffset Started, double Duration, long Bytes, string? Failure);

/// A header of a request or response.
public sealed record PageHeader(string Name, string Value);

/// Keeps the page rendering at `Width` by `Height` points while no window
/// shows it, so an agent's captures, scripts and input reach it, or lets it
/// rest again.
public sealed record HoldPageRendering(Guid PageId, bool Held, double Width, double Height) : PageRequest<bool>;

#endregion
