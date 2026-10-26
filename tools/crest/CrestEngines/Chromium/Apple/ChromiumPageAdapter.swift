#if CREST_CHROMIUM_HOST
    import AppKit

    /// The desktop Chromium adapter for one page. The engine presents its page
    /// through `ChromiumNativePage` as the page's engine-neutral events; this
    /// connects them, the page's context menu rows and its link drags to the
    /// page.
    @MainActor
    final class ChromiumPageAdapter: BrowserPageEngineAdapter {
        // MARK: - Variables

        let native: ChromiumNativePage
        private weak var page: BrowserPage?
        var engine: any BrowserPageEngine { native }
        let enginePage: EnginePage

        /// The engine reports hovered links itself.
        private(set) lazy var linkHover: BrowserLinkHoverController? =
            BrowserLinkHoverController(contentView: native.nativeView)
        private(set) lazy var linkDrag: BrowserLinkDragController? = BrowserLinkDragController(
            nativeView: native.nativeView,
            context: { [weak self] in self?.page?.navigationContext },
            dragsLinksToPeek: { [weak self] in self?.page?.corePage.linkPreferences?.dragsLinksToPeek == true },
            handle: { [weak self] event in self?.page?.handleLinkDrag(event) })
        private(set) lazy var pictureInPicture: (any BrowserPagePictureInPictureController)? =
            ChromiumPictureInPicturePageController(page: enginePage)
        // Chromium presents favicons and its error pages itself; reader and
        // content blocking are unavailable.
        var readerModeSession: BrowserReaderModeSession? { nil }
        var faviconSession: BrowserFaviconSession? { nil }
        var isContentBlockingActive: Bool { false }
        /// Chromium's binding reports the page's navigations to the core itself.
        var reporter: EnginePageReporter? { nil }
        /// Fills go through the engine's content scripting.
        var credentialEvaluator: BrowserCredentialSession.Evaluate? { nil }
        /// Translation runs through the engine's content scripting, in the
        /// page's main document.
        var translationDocument: BrowserTranslationDocument? { BrowserTranslationDocument(mainFrameOf: native) }

        // MARK: - Initializers

        init(_ native: ChromiumNativePage) {
            self.native = native
            enginePage = native.makeEnginePage()
        }

        // MARK: - Actions - Lifecycle

        /// Chromium reports the page's Media Session and runs its commands
        /// itself.
        func makeMediaSessionCoordinator(
            for page: BrowserPage,
            store: BrowserMediaSessionStore
        ) -> BrowserMediaSessionPageCoordinator? {
            BrowserMediaSessionPageCoordinator(
                transport: native, endpoint: page, store: store,
                owner: page.mediaSessionOwner, fallbackTitle: page.mediaSessionFallbackTitle)
        }

        func attach(to page: BrowserPage, allowsCredentialAccess: Bool) {
            self.page = page
            native.profileID = page.profileID
            native.observer = { [weak page] event in page?.receive(event) }
            native.promptPresenter = page
            native.menuHost = page
            native.linkDrag = linkDrag
            linkDrag?.observeNativeMouseDown()
        }

        func detach(from page: BrowserPage) {
            pictureInPicture?.invalidate()
            enginePage.close()
            native.dispose()
        }

        func setPrivateBrowsing(_ isPrivate: Bool) { native.isPrivateBrowsing = isPrivate }

        // MARK: - Actions - Engine-owned services

        /// Chromium's page view takes focus through its own responder chain.
        func install(_ focusRestoration: BrowserWebFocusRestorationController) {}
        /// The engine presents a person's input as `PageInteracted`.
        func monitorUserActivity(for page: BrowserPage) {}
        /// Chromium styles visited links from its own history.
        func styleVisitedLinks(history: [HistoryEntryState]) async {}
        /// The engine enforces site permissions itself; the page's permission
        /// session has already carried the change to it.
        func sitePermissionDidChange(_ permission: SitePermission, on page: BrowserPage) {}
    }

    extension BrowserPage {
        /// The Chromium page behind this page, or nil when another engine hosts it.
        var chromiumPage: ChromiumNativePage? { (engineAdapter as? ChromiumPageAdapter)?.native }
    }

    /// Chromium's browser Media Session can ask the active video player to enter
    /// PiP without page JavaScript or a synthetic click. The floating surface is
    /// still Chromium-owned; this controller only follows Crest's tab lifecycle.
    @MainActor
    private final class ChromiumPictureInPicturePageController:
        BrowserPagePictureInPictureController, BrowserAutomaticPictureInPictureClient
    {
        private let page: EnginePage
        private let coordinator: BrowserAutomaticPictureInPictureCoordinator
        private var completion: (@MainActor (Bool) -> Void)?
        private var check: Task<Void, Never>?

        var isPictureInPictureActive: Bool { page.mediaActivity.contains(.pictureInPicture) }
        var protectsPageResidency: Bool { isPictureInPictureActive || completion != nil }
        var canAutomaticallyEnterPictureInPicture: Bool {
            let activity = page.mediaActivity
            return activity.contains(.playing) && !activity.contains(.pictureInPicture)
        }

        init(page: EnginePage, coordinator: BrowserAutomaticPictureInPictureCoordinator = .shared) {
            self.page = page
            self.coordinator = coordinator
            coordinator.register(self)
        }

        func leaveTab() {
            coordinator.request(from: self)
        }
        func returnToTab() { coordinator.cancel(self) }

        func beginAutomaticPictureInPicture(completion: @escaping @MainActor (Bool) -> Void) {
            guard page.enterPictureInPicture() else {
                DiagnosticLog.pages.notice("Chromium page \(page.id) plays no video to float in Picture in Picture")
                completion(false)
                return
            }
            self.completion = completion
            check = Task { @MainActor [weak self] in
                // Media Session sends the request to the renderer. Check its
                // resulting browser state before releasing the reservation.
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                guard let self else { return }
                DiagnosticLog.pages.notice(
                    "Chromium page \(self.page.id) floats in Picture in Picture: \(self.isPictureInPictureActive)")
                self.completion?(self.isPictureInPictureActive)
                self.completion = nil
                self.check = nil
            }
        }

        func cancelAutomaticPictureInPicture() {
            check?.cancel()
            check = nil
            completion?(false)
            completion = nil
        }

        func invalidate() {
            coordinator.cancel(self)
        }
    }
#endif
