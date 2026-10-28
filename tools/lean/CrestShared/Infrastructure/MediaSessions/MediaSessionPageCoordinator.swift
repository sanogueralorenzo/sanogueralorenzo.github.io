import Foundation

/// How a page's Media Session state reaches Crest and Crest's commands reach
/// the page. WebKit runs Crest's bridge in the page's own world
/// (`BrowserWebKitMediaSessionTransport`); an engine with a native media
/// session reports it and executes the commands itself.
@MainActor
protocol BrowserMediaSessionTransport: AnyObject {
    /// The committed document's address, which every event must name.
    var mediaSessionLocation: String? { get }
    /// Starts reporting the current document under `documentIdentifier`.
    func activateMediaSession(documentIdentifier: String)
    func performMediaSessionAction(_ action: MediaSessionAction, documentIdentifier: String)
    func setMediaSessionMuted(_ muted: Bool, documentIdentifier: String)
}

/// Binds one resident page to the profile-owned Media Session store.
///
/// The coordinator accepts only main-frame messages from its own page and only
/// after that page commits the matching document URL. Navigation, process
/// loss, and page teardown all invalidate the endpoint before another document
/// is allowed to publish.
@MainActor
final class BrowserMediaSessionPageCoordinator {
    private weak var transport: (any BrowserMediaSessionTransport)?
    /// A transport built for this coordinator alone, which nothing else keeps.
    private(set) var ownedTransport: (any BrowserMediaSessionTransport)?
    private weak var endpoint: (any BrowserMediaSessionCommandEndpoint)?
    private let store: BrowserMediaSessionStore
    private let owner: @MainActor () -> BrowserTabRuntimeAssignment?
    private let fallbackTitle: @MainActor () -> String?
    private var documentIdentifier: String?

    init(
        transport: any BrowserMediaSessionTransport,
        endpoint: any BrowserMediaSessionCommandEndpoint,
        store: BrowserMediaSessionStore,
        owner: @escaping @MainActor () -> BrowserTabRuntimeAssignment?,
        fallbackTitle: @escaping @MainActor () -> String?
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.store = store
        self.owner = owner
        self.fallbackTitle = fallbackTitle
    }

    /// Binds a transport this coordinator keeps alive, for an engine that
    /// builds one per page.
    convenience init(
        owning transport: any BrowserMediaSessionTransport,
        endpoint: any BrowserMediaSessionCommandEndpoint,
        store: BrowserMediaSessionStore,
        owner: @escaping @MainActor () -> BrowserTabRuntimeAssignment?,
        fallbackTitle: @escaping @MainActor () -> String?
    ) {
        self.init(transport: transport, endpoint: endpoint, store: store, owner: owner, fallbackTitle: fallbackTitle)
        ownedTransport = transport
    }

    func prepareForNavigation() {
        invalidate()
        documentIdentifier = nil
    }

    func didCommitNavigation() {
        documentIdentifier = UUID().uuidString
        emitCurrentState()
    }

    func didFinishNavigation() {
        emitCurrentState()
    }

    /// A custom tab rename is Crest state rather than page Media Session state.
    /// Ask the same bounded bridge for a fresh sequenced event so the shared
    /// store can publish the new owner title without creating another truth.
    func ownerTitleDidChange() {
        emitCurrentState()
    }

    private func emitCurrentState() {
        guard let documentIdentifier else { return }
        transport?.activateMediaSession(documentIdentifier: documentIdentifier)
    }

    func webContentProcessDidTerminate() {
        invalidate()
        documentIdentifier = nil
    }

    func prepareForRemoval() {
        invalidate()
        documentIdentifier = nil
        transport = nil
        ownedTransport = nil
        endpoint = nil
    }

    func receive(_ body: Any, isMainFrame: Bool) {
        guard let event = BrowserMediaSessionPageEventDecoder.decode(body) else { return }
        receive(event, isMainFrame: isMainFrame)
    }

    /// A session event an engine reports in the model itself rather than as a
    /// page script's message body.
    func receive(_ event: BrowserMediaSessionPageEvent, isMainFrame: Bool) {
        guard let documentIdentifier,
            isMainFrame,
            let transport,
            let endpoint,
            let owner = owner(),
            event.documentIdentifier == documentIdentifier,
            event.location == transport.mediaSessionLocation
        else { return }
        store.receive(
            event,
            owner: owner,
            fallbackTitle: fallbackTitle(),
            endpoint: endpoint
        )
    }

    func perform(
        _ action: MediaSessionAction,
        documentIdentifier: String
    ) {
        guard self.documentIdentifier == documentIdentifier,
            documentIdentifier.count
                <= BrowserMediaSessionPageEventDecoder.maximumDocumentIdentifierLength
        else { return }
        transport?.performMediaSessionAction(action, documentIdentifier: documentIdentifier)
    }

    /// Muting is an element property rather than a Media Session action, so it
    /// travels the same validated path as `perform`.
    func setMuted(
        _ muted: Bool,
        documentIdentifier: String
    ) {
        guard self.documentIdentifier == documentIdentifier,
            documentIdentifier.count
                <= BrowserMediaSessionPageEventDecoder.maximumDocumentIdentifierLength
        else { return }
        transport?.setMediaSessionMuted(muted, documentIdentifier: documentIdentifier)
    }

    private func invalidate() {
        guard let endpoint else { return }
        store.invalidate(endpoint: endpoint)
    }
}
