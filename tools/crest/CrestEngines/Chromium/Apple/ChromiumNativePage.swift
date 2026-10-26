#if CREST_CHROMIUM_HOST
    import AppKit
    import Observation

    /// Hosts the view of one Chromium page. Chromium's C++ binding creates,
    /// loads and closes the page when the core asks, under the identity the
    /// core gave it, and tells the core what it does; this reports nothing. It
    /// presents the page to this one: what its view shows, as the page's
    /// engine-neutral events. The page's direct requests, such as going back
    /// or capturing it, go through its shared `EnginePage`.
    @Observable @MainActor
    final class ChromiumNativePage: BrowserPageEngine {
        let registration = BrowserEngineRegistration.chromium
        /// The core's identity for this page.
        let pageID: UUID
        /// The name the engine uses for this page: the core's identity.
        let id: String
        let surface = ChromiumNativePageView()
        var isPrivateBrowsing: Bool
        /// The profile of the page's Space, once its owner names it.
        var profileID: UUID?
        /// The engine that hosts the page, which its direct requests go to.
        private weak var engine: ChromiumEngine?
        var observer: (any BrowserPageEngineEvent) -> Void
        /// The platform's page hosting this one, which shows the person the
        /// core's questions about it.
        weak var promptPresenter: (any BrowserPromptPresenting)?
        /// The platform's page hosting this one, which puts Crest's rows in the
        /// engine's context menu for it.
        weak var menuHost: (any BrowserPageContextMenuHost)?
        /// Crest's own drag of a link out of the page.
        weak var linkDrag: BrowserLinkDragController?
        private var host: (any CrestMacShell)? { engine?.host }
        private var created = false
        /// Whether the engine shows the page now, as this page last asked it
        /// to, so a surface that joins its window and its host at once, or a
        /// host told twice, asks once.
        private var isShown = false
        private(set) var disposed = false
        /// What waits for the engine: each script evaluation by its identity.
        var evaluations: [UUID: CheckedContinuation<String?, Never>] = [:]
        /// Whether the page's tab shows its sound, so a page the engine creates
        /// after its tab began showing it starts measuring as it is created.
        @ObservationIgnored private var observesSpectrum = false
        /// The engine's measure of the sound the page plays, which it takes
        /// only while the page's tab shows it.
        @ObservationIgnored
        private(set) lazy var audioSpectrum: BrowserAudioSpectrumFeed? = BrowserAudioSpectrumFeed(observe: {
            [weak self] observed in
            guard let self else { return }
            observesSpectrum = observed
            guard created else { return }
            pages?.request(ObserveAudioSpectrum(pageID: pageID, observed: observed))
        })

        /// A page the core opened, which Chromium's binding creates.
        init(id: UUID, engine: ChromiumEngine) {
            pageID = id
            self.id = id.uuidString
            self.engine = engine
            isPrivateBrowsing = false
            observer = { _ in }
            surface.page = self
            // The binding may have created the page before its view came.
            engine.pages.request(WatchPage(pageID: id))
        }

        /// The page's direct path to the binding, while the engine is running.
        private var pages: NativeEnginePages? { disposed ? nil : engine?.pages }

        /// The shared direct path to this page. Chromium restores its history
        /// in place of the page's first load, and starts its inspector on the
        /// Console or Elements, never the Network panel.
        func makeEnginePage() -> EnginePage {
            guard let engine else { preconditionFailure("A Chromium page came without its engine.") }
            return EnginePage(
                id: pageID, pages: engine.pages, historyFamily: .chromium,
                historyVersion: { [weak self] in self?.engine?.version },
                inspectorPanels: [.console, .elements])
        }

        var nativeView: NSView { surface }
        /// The link the engine staged in another page becomes this page's first
        /// load, through the core, which checks the two pages share an engine
        /// and a profile.
        func stageNavigation(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool {
            guard !created, !disposed, let engine,
                navigation.implementation == registration.implementationId,
                let sourcePageID = navigation.sourcePageID
            else { return false }
            return engine.stage(navigation.linkID, from: sourcePageID, into: pageID, expecting: url)
        }
        var currentURL: URL?
        /// The binding presents the page's loading and failures, so the page
        /// reads them from its presentations.
        var reportsNavigationState: Bool { true }

        func load(_ request: URLRequest) {
            guard let url = request.url else { return }
            load(url)
        }
        /// The app's own load of `url`, which the core resolves and asks the
        /// binding to run.
        func load(_ url: URL) {
            guard !disposed else { return }
            engine?.navigate(pageID, to: url)
        }

        /// Puts the page's view in its surface once the binding created the
        /// page and the surface is in a window, and shows the page there, as
        /// its window's own page, while its host has it on screen: presented,
        /// or in the preview of a Space the person swipes to or from, which
        /// never takes focus. A host whose Space is off screen keeps the page
        /// hidden from the engine.
        func attachIfPossible(takingFocus takesFocus: Bool = true) {
            guard !disposed, created, let window = surface.window,
                let windowID = window.identifier.flatMap({ UUID(uuidString: $0.rawValue) }), let pages
            else { return }
            guard surface.presentation != .hidden else {
                if let view = host?.view(forPage: pageID) { embed(view) }
                detach()
                return
            }
            guard pages.request(MovePageToWindow(pageID: pageID, windowID: windowID)),
                let view = host?.view(forPage: pageID)
            else { return }
            embed(view)
            guard !isShown else { return }
            show(in: window, takingFocus: takesFocus && surface.presentation == .presented)
        }

        /// The host showing the page's view changed how it shows it, as its
        /// Space did: the page comes back on screen, or leaves it, as it does
        /// when the person switches tabs. A page its Space's preview kept on
        /// screen through a swipe is shown again as the Space settles, which
        /// focuses it as it would a page coming on screen.
        func presentationDidChange(takingFocus takesFocus: Bool) {
            guard surface.presentation != .hidden else {
                detach()
                return
            }
            guard isShown, surface.presentation == .presented else {
                attachIfPossible(takingFocus: takesFocus)
                return
            }
            guard takesFocus, let window = surface.window else { return }
            show(in: window, takingFocus: true)
        }

        /// Focuses the page while it is on screen, as the engine does a page it
        /// shows: its render view takes the keys. AppKit alone would stop at
        /// the engine's outer view, which holds focus without passing keys on.
        func focusShownPage() -> Bool {
            guard isShown, surface.presentation == .presented, let window = surface.window else { return false }
            show(in: window, takingFocus: true)
            guard let responder = window.firstResponder as? NSView else { return false }
            return responder.isDescendant(of: surface)
        }

        /// Asks the engine to show the page. The engine focuses a page it
        /// shows; one that may not take focus hands it back to what held it.
        private func show(in window: NSWindow, takingFocus takesFocus: Bool) {
            guard let pages else { return }
            let responder = window.firstResponder
            let shown = pages.request(ShowPage(pageID: pageID))
            isShown = shown
            DiagnosticLog.pages.notice("Chromium page \(pageID) shows (shown: \(shown), focus: \(takesFocus))")
            guard !takesFocus, window.firstResponder !== responder else { return }
            window.makeFirstResponder(Self.focusOwner(of: responder))
        }

        private func embed(_ view: NSView) {
            guard view.superview !== surface else { return }
            view.removeFromSuperview()
            view.frame = surface.bounds
            view.autoresizingMask = [.width, .height]
            surface.addSubview(view)
        }

        /// What takes focus back from a page the engine focused: a text
        /// field whose field editor held it, or the responder itself.
        private static func focusOwner(of responder: NSResponder?) -> NSResponder? {
            guard let editor = responder as? NSTextView, editor.isFieldEditor,
                let field = editor.delegate as? NSResponder
            else { return responder }
            return field
        }

        // MARK: Content bridges

        private var contentScripts: [BrowserContentScript] = []
        private(set) var contentReceivers: [String: @MainActor (BrowserContentMessage) -> Void] = [:]
        var contentScripting: (any BrowserPageContentScripting)? { self }

        /// The committed document's address, which the page's Media Session
        /// names.
        var mediaSessionLocation: String?

        /// The extension actions the page's toolbar offers, with each one's state
        /// for the page's own tab.
        var extensions: [BrowserExtensionActionPresentation] {
            guard created, let pages else { return [] }
            return pages.request(PageExtensions(pageID: pageID)).actions.map(BrowserExtensionActionPresentation.init)
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }

        func runExtension(_ extensionID: String, anchor: BrowserExtensionPopupAnchor? = nil) {
            guard created, !disposed else { return }
            let anchor =
                anchor ?? BrowserExtensionPopupAnchor(screenPoint: NSEvent.mouseLocation, sourceWindow: surface.window)
            guard let source = anchor.presentationSource(fallbackWindow: surface.window) else { return }
            if host?.runExtension(extensionID, page: pageID, anchorView: source.view, anchorRect: source.rect) != true {
                ChromiumComposition.showNativeNotice(
                    "This extension action is unavailable on this page.", icon: "puzzlepiece.extension")
            }
        }

        /// Which side panel `extensionID` has for this page's own tab.
        func sidePanelScope(_ extensionID: String) -> SidePanelScope {
            guard created, let pages else { return .unavailable }
            return pages.request(HasSidePanel(pageID: pageID, extensionID: extensionID))
        }

        /// Whether this page's panel for `extensionID` also belongs beside the
        /// page `pageID` names: both are tabs of one profile for which the
        /// extension shows its panel for every tab, so one document serves both.
        func sharesSidePanel(_ extensionID: String, with pageID: UUID) -> Bool {
            guard let other = engine?.page(pageID), other !== self, let profileID, other.profileID == profileID
            else { return false }
            return sidePanelScope(extensionID) == .window && other.sidePanelScope(extensionID) == .window
        }

        /// Creates the panel document and returns its view for the core to mount.
        /// `closed` runs when the panel or its extension host goes away on its own.
        func openSidePanel(_ extensionID: String, closed: @escaping () -> Void) -> NSView? {
            guard created, !disposed, let host else { return nil }
            return host.openSidePanel(extensionID, page: pageID, closed: closed)
        }

        func closeSidePanel() {
            guard created, !disposed else { return }
            host?.closeSidePanel(page: pageID)
        }

        /// Mounts, relayouts or removes the docked DevTools frontend the engine is
        /// offering for this page.
        ///
        /// A docked inspector belongs to the card it inspects, not to the window:
        /// the frontend is a subview of this page's own surface, below the page so
        /// the page can be drawn on top of it at the rectangle the frontend asked
        /// for. Undocking withdraws the offer — Chromium then opens the window the
        /// user asked for — and so does closing the inspector by any route.
        func refreshDevTools() {
            guard !disposed, let host else { return }
            surface.devToolsView = host.devToolsView(page: pageID)
            surface.layoutEngineView()
        }

        /// Where the docked inspector and the page go in a card of `size`.
        func layoutInspector(in size: CGSize) -> InspectorLayout? {
            guard created, let pages else { return nil }
            return pages.request(LayoutInspector(pageID: pageID, width: size.width, height: size.height))
        }

        /// The inspector for this page is going away, whatever closed it. The core
        /// clears its developer-panel selection so the next Console or Elements
        /// command opens an inspector instead of trying to close a closed one.
        func developerPanelDidClose() {
            guard !disposed else { return }
            observer(BrowserPageDeveloperPanelClosed())
        }

        /// The Chrome Web Store listing this page is showing asked Crest to install
        /// or remove the extension it is about. The engine has already checked that
        /// the extension is the one the page's own URL names, and the destination is
        /// this page's own Space — a listing can never reach another Space or a
        /// private window, which keeps no persistent extension state.
        func performStoreRequest(_ extensionID: String, removes: Bool) {
            let store = ChromiumComposition.extensions
            guard !isPrivateBrowsing, let profileID,
                let space = ChromiumComposition.extensionSpace(forProfile: profileID)
            else {
                refreshStoreState()
                return
            }
            let refresh: @MainActor () -> Void = { [weak self] in self?.refreshStoreState() }
            if removes {
                store.confirmRemoval(extensionID, in: space, completion: refresh)
            } else {
                store.install(extensionID, in: space, anchor: surface, completion: refresh)
            }
        }

        /// Restates the listing's install button from Chromium's own registry once
        /// an install review has finished, been canceled, or was never offered.
        private func refreshStoreState() {
            guard created else { return }
            pages?.request(RefreshStoreListing(pageID: pageID))
        }

        /// The extension a store listing names. A listing is `/detail/<id>` or
        /// `/detail/<name>/<id>`, and its reviews and support pages add a segment
        /// after the identifier.
        static func webStoreExtensionID(_ url: URL?) -> String? {
            guard let url, url.scheme == "https", url.host == "chromewebstore.google.com"
            else { return nil }
            let parts = Array(url.pathComponents.dropFirst())
            guard parts.count >= 2, parts[0] == "detail" else { return nil }
            let isID: (String) -> Bool = { candidate in
                candidate.count == 32 && candidate.allSatisfy({ ("a"..."p").contains(String($0)) })
            }
            if parts.count > 2, isID(parts[2]) { return parts[2] }
            return isID(parts[1]) ? parts[1] : nil
        }

        /// A page still being created takes the zoom once it exists.
        func detach() {
            guard created, isShown else { return }
            isShown = false
            DiagnosticLog.pages.notice("Chromium page \(pageID) hides")
            pages?.request(HidePage(pageID: pageID))
            observer(BrowserPageLeftScreen())
        }

        /// The page's owner let it go. The core's ClosePage has the binding
        /// close what the engine holds.
        func dispose() {
            guard !disposed else { return }
            disposed = true
            BrowserExtensionSidePanelHosts.release(pageID)
            surface.devToolsView = nil
            for subview in surface.subviews { subview.removeFromSuperview() }
            for (_, evaluation) in evaluations { evaluation.resume(returning: nil) }
            evaluations = [:]
        }

        /// A script dialog the core asks the person, answered once they answer it.
        func ask(_ asked: ScriptDialogAsked, dismissal: BrowserPromptDismissal) {
            guard let promptPresenter else {
                engine?.answer(AnswerScriptDialog(promptID: asked.promptID, accepted: false, text: nil))
                return
            }
            promptPresenter.ask(asked, dismissal: dismissal)
        }

        /// A server's request for a user name and password. The credential goes
        /// to the core, which hands it to the engine and keeps no copy.
        func ask(_ asked: AuthenticationAsked, dismissal: BrowserPromptDismissal) {
            guard let promptPresenter else {
                engine?.answer(AnswerAuthentication(promptID: asked.promptID, credential: nil))
                return
            }
            promptPresenter.ask(asked, dismissal: dismissal)
        }

        /// A site's permission request its Space's choices do not answer. The
        /// core records an answer the person asks it to remember.
        func ask(_ asked: PermissionAsked, dismissal: BrowserPromptDismissal) {
            guard let promptPresenter else {
                engine?.answer(AnswerPermission(promptID: asked.promptID, grants: false, remembers: false))
                return
            }
            promptPresenter.ask(asked, dismissal: dismissal)
        }

        /// The engine created the page: the page's scripts go in, its sound is
        /// measured if its tab already shows it, and its view goes on screen if
        /// it has a window to go in.
        func viewReady() {
            guard !created else { return }
            created = true
            for script in contentScripts {
                pages?.request(
                    AddContentScript(pageID: pageID, source: script.source, mainFrameOnly: script.mainFrameOnly))
            }
            if observesSpectrum {
                pages?.request(ObserveAudioSpectrum(pageID: pageID, observed: true))
            }
            attachIfPossible()
        }

        // MARK: Menus and drags

        /// Puts Crest's rows for `link` or `selection` in the engine's context
        /// menu for this page.
        func addMenuItems(to menu: NSMenu, link: URL?, selection: String?) {
            guard !disposed, let menuHost else { return }
            BrowserPageContextMenu(
                actions: menuHost.contextMenuActions(linkURL: link, selectionText: selection), host: menuHost,
                view: surface
            ).insert(into: menu)
        }

        /// Starts Crest's own drag of the link to `url` out of the page; false
        /// leaves the drag to the engine.
        func beginLinkDrag(_ url: URL, title: String) -> Bool {
            guard !disposed, ExternalWebLink.accepts(url) else { return false }
            return linkDrag?.beginNativeLink(url: url, label: title) == true
        }
    }

    @MainActor
    final class ChromiumNativePageView: NSView, BrowserNativePageSurfaceLifecycle {
        weak var page: ChromiumNativePage?
        /// The docked DevTools frontend, while one is offered for this page. It is
        /// kept below the engine's page view so the page is drawn on top of it,
        /// which is the arrangement the resizing strategy is expressed in.
        var devToolsView: NSView? {
            didSet {
                guard devToolsView !== oldValue else { return }
                oldValue?.removeFromSuperview()
                guard let devToolsView else { return }
                devToolsView.autoresizingMask = []
                if let engineView {
                    addSubview(devToolsView, positioned: .below, relativeTo: engineView)
                } else {
                    addSubview(devToolsView)
                }
            }
        }
        /// The engine's page view. The DevTools frontend is a sibling, so the page
        /// is whichever subview is not it.
        private var engineView: NSView? {
            subviews.first { $0 !== devToolsView }
        }
        override func layout() {
            super.layout()
            layoutEngineView()
        }
        override func resizeSubviews(withOldSize oldSize: NSSize) {
            layoutEngineView()
        }
        func layoutEngineView() {
            guard !bounds.isEmpty, let view = engineView else { return }
            guard let devToolsView, let layout = page?.layoutInspector(in: bounds.size),
                let frontendFrame = layout.inspector.map({ frame(of: $0) }),
                let pageFrame = layout.page.map({ frame(of: $0) })
            else {
                view.isHidden = false
                view.frame = bounds
                // A navigation can replace Chromium's renderer after this container
                // was laid out. Propagate the viewport even when its size is unchanged.
                view.setFrameSize(bounds.size)
                return
            }
            devToolsView.frame = frontendFrame
            devToolsView.setFrameSize(frontendFrame.size)
            // An empty page rectangle is the frontend asking to cover the page —
            // its own device-toolbar and drawer layouts do this — so the page is
            // hidden rather than squeezed to nothing.
            view.isHidden = pageFrame.isEmpty
            guard !pageFrame.isEmpty else { return }
            view.frame = pageFrame
            view.setFrameSize(pageFrame.size)
        }

        /// An area the binding measured from the card's top left, as AppKit
        /// measures it, from the bottom left.
        private func frame(of area: PageArea) -> CGRect {
            CGRect(
                x: bounds.minX + area.x, y: bounds.minY + bounds.height - area.y - area.height,
                width: area.width, height: area.height)
        }
        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool {
            // The page, never the docked inspector beside it: focus arriving at the
            // card belongs to the page the card is showing.
            guard let view = engineView else { return super.becomeFirstResponder() }
            if page?.focusShownPage() == true { return true }
            return window?.makeFirstResponder(view) ?? false
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            // AppKit takes first responder from a view leaving its window without
            // telling it. Chromium's page view, still thinking it has focus, then
            // deactivates the page, and that can land after the page is focused
            // again in its next host, leaving it focused but inactive: it ignores
            // cursor changes made without the pointer moving, such as a fullscreen
            // video hiding the idle pointer. Giving up focus first makes leaving
            // an ordinary loss of focus.
            if let window, newWindow !== window, let responder = window.firstResponder as? NSView,
                responder.isDescendant(of: self)
            {
                window.makeFirstResponder(nil)
            }
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { page?.attachIfPossible() } else { page?.detach() }
        }
        func didAttach(to host: BrowserWebHostView) { page?.attachIfPossible() }
        /// A Chromium page shown again composes a new frame before it draws
        /// anything; see `BrowserNativePageSurfaceLifecycle`.
        var holdsReplacedPageUntilDrawn: Bool { true }
        func willDetach(from host: BrowserWebHostView) { page?.detach() }
        func presentationDidChange(in host: BrowserWebHostView) {
            page?.presentationDidChange(takingFocus: host.allowsPageFocus)
        }
        func presentationGeometryDidChange() { layoutEngineView() }
        /// How the host this surface is in shows its page.
        var presentation: BrowserPagePresentation {
            (superview as? BrowserWebHostView)?.presentation ?? .presented
        }
    }
    extension ChromiumNativePage: BrowserPageContentScripting {
        func install(_ script: BrowserContentScript, receive: @escaping @MainActor (BrowserContentMessage) -> Void)
            -> Bool
        {
            guard !disposed else { return false }
            contentScripts.append(script)
            contentReceivers[script.handlerName] = receive
            if created, let pages {
                return pages.request(
                    AddContentScript(pageID: pageID, source: script.source, mainFrameOnly: script.mainFrameOnly))
            }
            return true
        }

        func callAsyncJavaScript(_ body: String, arguments: [String: Any], in frame: BrowserContentFrame) async throws
            -> Any?
        {
            guard created, !disposed, let frameID = frame.handle as? String else { return nil }
            return await evaluate(try Self.binding(arguments, to: body), in: frameID)
        }

        func callAsyncJavaScriptInMainFrame(_ body: String, arguments: [String: Any]) async throws -> Any? {
            guard created, !disposed else { return nil }
            // The engine addresses the primary main frame's current document by
            // this name.
            return await evaluate(try Self.binding(arguments, to: body), in: "main")
        }

        /// `body` with `arguments` bound as constants named for their keys, as
        /// WebKit's callAsyncJavaScript binds them.
        private static func binding(_ arguments: [String: Any], to body: String) throws -> String {
            guard !arguments.isEmpty else { return body }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
            var source = "const __crestArguments = \(json);\n"
            for key in arguments.keys.sorted() { source += "const \(key) = __crestArguments[\"\(key)\"];\n" }
            return source + body
        }

        /// Runs `source` in the document `frameID` names and answers the value of
        /// its result, or nil when the document is gone.
        private func evaluate(_ source: String, in frameID: String) async -> Any? {
            guard created, let pages else { return nil }
            let evaluationID = UUID()
            let result: String? = await withCheckedContinuation { continuation in
                guard
                    pages.request(
                        EvaluateContentScript(
                            pageID: pageID, evaluationID: evaluationID, source: source, frameID: frameID))
                else {
                    continuation.resume(returning: nil)
                    return
                }
                evaluations[evaluationID] = continuation
            }
            guard let data = result?.data(using: .utf8),
                let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                !(value is NSNull)
            else { return nil }
            return value
        }
    }
    extension ChromiumNativePage: BrowserMediaSessionTransport {
        func activateMediaSession(documentIdentifier: String) {
            guard created else { return }
            pages?.request(ActivateMediaSession(pageID: pageID, document: documentIdentifier))
        }

        func performMediaSessionAction(_ action: MediaSessionAction, documentIdentifier: String) {
            guard created else { return }
            pages?.request(
                PerformMediaAction(pageID: pageID, document: documentIdentifier, action: action))
        }

        func setMediaSessionMuted(_ muted: Bool, documentIdentifier: String) {
            guard created else { return }
            pages?.request(MuteMediaSession(pageID: pageID, document: documentIdentifier, muted: muted))
        }
    }

    extension BrowserMediaSessionPageEvent {
        /// The session the binding presented, as Crest's media store takes it,
        /// within the bounds a page script's report is held to.
        init?(_ session: MediaSessionChanged) {
            typealias Bounds = BrowserMediaSessionPageEventDecoder
            guard !session.document.isEmpty, session.document.count <= Bounds.maximumDocumentIdentifierLength,
                session.location.count <= Bounds.maximumLocationLength
            else { return nil }
            func bounded(_ text: String?) -> String? {
                guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
                    trimmed.count <= Bounds.maximumTextLength
                else { return nil }
                return trimmed
            }
            let playback: BrowserMediaSessionPlaybackState
            switch session.playback {
            case .none: playback = .none
            case .playing: playback = .playing
            case .paused: playback = .paused
            }
            self.init(
                documentIdentifier: session.document, sequence: UInt64(max(session.sequence, 0)),
                location: session.location, isInvalidated: false, hasActiveSession: session.active,
                title: bounded(session.title), artist: bounded(session.artist), album: bounded(session.album),
                artworkData: session.artwork.flatMap {
                    $0.count <= BrowserMediaSessionPageEventDecoder.maximumArtworkBytes ? $0 : nil
                },
                playbackState: playback, isAudible: session.audible, isMuted: session.muted,
                availableActions: Set(session.actions))
        }
    }

#endif
