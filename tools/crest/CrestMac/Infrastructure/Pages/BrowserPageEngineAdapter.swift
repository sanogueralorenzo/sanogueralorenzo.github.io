import AppKit
import Foundation

/// The desktop half of an engine adapter for one page: the wiring the engine
/// needs into the page it hosts, and the page controllers only that engine can
/// build. The engine's binding builds it when the core asks the engine to
/// create a page. `BrowserPage` holds one and reaches its engine only through
/// it and the `BrowserPageEngine` port.
@MainActor
protocol BrowserPageEngineAdapter: EngineHostedPage {
    var engine: any BrowserPageEngine { get }
    /// The page's direct path to its engine: going back, reloading, finding
    /// text, capturing and exporting the page, and carrying Crest's site
    /// decisions to it.
    var enginePage: EnginePage { get }

    var linkHover: BrowserLinkHoverController? { get }
    var linkDrag: BrowserLinkDragController? { get }
    var pictureInPicture: (any BrowserPagePictureInPictureController)? { get }
    var readerModeSession: BrowserReaderModeSession? { get }
    var faviconSession: BrowserFaviconSession? { get }
    var isContentBlockingActive: Bool { get }
    /// Tells the core what the page's engine shows and what its navigations
    /// do, once the adapter is attached to its page.
    var reporter: EnginePageReporter? { get }
    /// Evaluates a credential fill in the document that asked for it, for an
    /// engine whose bridges are not installed through `contentScripting`.
    var credentialEvaluator: BrowserCredentialSession.Evaluate? { get }
    /// The page's main document as whole-page translation rewrites it, or
    /// nil for an engine that does not translate whole pages.
    var translationDocument: BrowserTranslationDocument? { get }

    /// Builds the page's Media Session coordinator: over Crest's bridge in the
    /// page, or over an engine that reports the session itself.
    func makeMediaSessionCoordinator(
        for page: BrowserPage,
        store: BrowserMediaSessionStore
    ) -> BrowserMediaSessionPageCoordinator?
    /// Wires the engine's delegates, bridges and observers to `page`, once.
    func attach(to page: BrowserPage, allowsCredentialAccess: Bool)
    /// Releases everything `attach` installed. The page is going away.
    func detach(from page: BrowserPage)

    /// Lets the engine view take part in restoring the page's editing focus.
    func install(_ focusRestoration: BrowserWebFocusRestorationController)
    /// Starts reporting the person's input in the page as `.userActivity`.
    func monitorUserActivity(for page: BrowserPage)
    func styleVisitedLinks(history: [HistoryEntryState]) async
    /// Runs after a change to one of the page's site permissions reached the
    /// engine, so bridges the adapter runs inside the page follow it.
    func sitePermissionDidChange(_ permission: SitePermission, on page: BrowserPage)
    func setPrivateBrowsing(_ isPrivate: Bool)
}

/// The page's PiP lifecycle follows tab presentation, regardless of which
/// engine owns the video and its floating window. The controller asks for
/// automatic entry as its tab leaves the screen, and withdraws a request still
/// pending as the tab returns. A video already floating returns to the page
/// because the core ends it once a window shows the page again.
@MainActor
protocol BrowserPagePictureInPictureController: AnyObject {
    var canRestoreSource: Bool { get }
    var protectsPageResidency: Bool { get }
    func leaveTab()
    func returnToTab()
    func navigationDidCommit()
    func nativePresentationDidChange(isActive: Bool)
    func invalidate()
}

extension BrowserPagePictureInPictureController {
    var canRestoreSource: Bool { false }
    var protectsPageResidency: Bool { false }
    func navigationDidCommit() {}
    func nativePresentationDidChange(isActive: Bool) {}
}
