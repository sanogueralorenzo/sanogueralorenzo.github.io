import Foundation
import WebKit

/// WebKit's binding, on the Mac and on iPhone and iPad. It builds each page
/// the core asks WebKit to create: the page's configuration for its profile,
/// with the platform's own settings, in the profile's website data store and
/// with its Space's content rules, and the platform's web view, which the
/// page's owner then hosts. It keeps each profile's store itself: a private
/// page's profile, and every profile of a launch that keeps nothing on disk,
/// lives in a store of its own in memory, which goes when the core erases the
/// profile, as private browsing ending does; any other profile opens its
/// store on disk. It runs each load the core asks for in the page, once the
/// page's host is ready for it. A page the core closes keeping its state hands
/// the core WebKit's history and the address it shows, which the tab's next
/// page brings back in place of its first load; a popup and a private page
/// keep nothing. The owner tears the web view down when it releases the page.
/// Each page tells the binding when its media starts or stops, so the page
/// reports the media it runs to the core as that changes. The questions a
/// page's document asks go to the core, which the page's host shows the
/// person, and come back as the core settles them. The files its pages
/// download run as WebKit's own downloads, which it reports to the core. It
/// erases what WebKit keeps for a profile when the core asks, whether or not
/// any page of it opened this run.
@MainActor
final class WebKitEngineBinding: EngineBinding {
    // MARK: - Types

    struct WeakPage {
        weak var value: WebKitEnginePage?
    }

    struct WeakStore {
        weak var value: WKWebsiteDataStore?
    }

    /// A popup WebKit made for one of this binding's pages, which the page
    /// offered the core while WebKit waits: the configuration WebKit derived
    /// from the opener's, and the Space the opener browses in.
    struct Offer {
        let popup: WebKitPopup
        let space: SpaceModel?
        /// The page that asked for the window.
        let sourcePageID: UUID
        /// What the window was asked to load, which the page that asked for it
        /// loads instead when the core keeps the window in that page.
        let request: URLRequest
    }

    /// A modified link's request one of this binding's pages staged for the
    /// Peek the core opens for it, which replays the initiator's referrer.
    struct StagedLink {
        let request: URLRequest
        /// The page the link was followed in.
        let sourcePageID: UUID
        /// The store the source page browses in, which the Peek's page must
        /// share.
        weak var dataStore: WKWebsiteDataStore?
        let stagedAt: Date
    }

    // MARK: - Static Variables

    /// How long a staged link waits for its Peek, and how many may wait.
    private static let stagedLinkLifetime: TimeInterval = 300
    private static let stagedLinkLimit = 16

    // MARK: - Variables

    let integration = BrowserEngineRegistration.webKit
    private(set) weak var engines: Engines?
    /// Removes a profile's stores, which WebKit keeps on disk across runs.
    let profileStores: any BrowserEngineProfileRemoving
    /// Whether every profile keeps its website data in memory only, as an
    /// isolated launch's do.
    private let keepsProfilesInMemory: Bool
    /// The store each profile that keeps nothing on disk browses in, until the
    /// core erases the profile: every private profile's, and every profile's
    /// when the launch keeps nothing on disk.
    var memoryStores: [UUID: WKWebsiteDataStore] = [:]
    /// The store on disk each other profile's pages use, while one holds it,
    /// which its next page shares and a site's data is cleared from.
    private(set) var liveStores: [UUID: WeakStore] = [:]
    /// The content rules every page this binding builds applies, compiled once.
    let contentRules: WebKitContentRules
    /// The files this binding's pages download, which the core records.
    private(set) lazy var downloads = WebKitDownloads(binding: self)
    /// The pages' direct path to the views this binding built.
    private(set) lazy var enginePages = WebKitEnginePages(binding: self)
    /// The pages this binding built, while their owners keep them.
    var pages: [UUID: WeakPage] = [:]
    /// The questions this binding's pages raised, by prompt, until the core
    /// settles them.
    var prompts: [UUID: any WebKitPendingPrompt] = [:]
    /// How to close what each page's host shows for a question, until the
    /// question no longer waits.
    private var dismissals: [UUID: BrowserPromptDismissal] = [:]
    /// The links this binding's pages staged, by the identity the core
    /// stages them under, until a page loads one or the core drops it.
    var stagedLinks: [UUID: StagedLink] = [:]
    /// The popups this binding's pages offered the core, by offer, while the
    /// core decides on them.
    var offers: [UUID: Offer] = [:]
    /// The page this binding built for each offer the core adopted, until the
    /// page that offered it hands it to WebKit.
    var adoptedOffers: [UUID: WebKitEnginePage] = [:]

    // MARK: - Initializers

    /// A binding whose profiles' stores `profileStores` removes, which keeps
    /// every profile in memory when `keepsProfilesInMemory`, and whose pages'
    /// content rules `contentRuleLists` compiles; nil compiles the core's
    /// rules as the launch allows.
    init(
        profileStores: any BrowserEngineProfileRemoving = WebKitBrowserWebsiteDataStoreRemover(),
        keepsProfilesInMemory: Bool = BrowserLaunchEnvironment.current.usesEphemeralProfileStorage,
        contentRuleLists: (any BrowserContentRuleListProviding)? = nil
    ) {
        self.profileStores = profileStores
        self.keepsProfilesInMemory = keepsProfilesInMemory
        contentRules = WebKitContentRules(provider: contentRuleLists)
    }

    // MARK: - Actions - Binding

    func attach(to engines: Engines) {
        self.engines = engines
        if contentRules.provider == nil {
            contentRules.provider = BrowserContentRuleListProvider.forLaunch(core: engines.core)
        }
        engines.core.followPrompts(self)
    }

    func run(_ command: EngineCommand) {
        guard engines != nil else { return }
        command.perform(on: self)
    }

    /// The core this binding reports to, while it is attached.
    var core: CrestCore? { engines?.core }

    /// The page this binding built as `pageID`, while its owner keeps it.
    func page(_ pageID: UUID) -> WebKitEnginePage? {
        pages[pageID]?.value
    }

    /// Reports what one of this binding's pages or downloads did.
    func report(_ event: some EngineEvent) {
        engines?.report(event, from: self)
    }

    /// What the core answers about one of this binding's pages while WebKit
    /// waits; nil while the binding is not registered.
    func ask<Question: EngineQuestion>(_ question: Question) -> Question.Answer? {
        engines?.ask(question, from: self)
    }

    // MARK: - Actions - Staged links

    /// Keeps the request of a modified link `page` followed under a new
    /// identity, so the Peek the core opens for it replays the initiator's
    /// referrer instead of a bare address. Only a plain GET is staged: WebKit
    /// has no public way to hand another view a form body, the initiating
    /// origin, user activation or sandbox flags.
    func stageLink(_ request: URLRequest, from page: WebKitEnginePage) -> BrowserEngineNavigation? {
        guard let url = request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            (request.httpMethod ?? "GET").uppercased() == "GET",
            request.httpBody == nil, request.httpBodyStream == nil
        else { return nil }
        let now = Date()
        stagedLinks = stagedLinks.filter {
            $0.value.dataStore != nil && now.timeIntervalSince($0.value.stagedAt) < Self.stagedLinkLifetime
        }
        if stagedLinks.count >= Self.stagedLinkLimit,
            let oldest = stagedLinks.min(by: { $0.value.stagedAt < $1.value.stagedAt })?.key
        {
            stagedLinks[oldest] = nil
        }
        var replay = URLRequest(url: url, cachePolicy: request.cachePolicy)
        if let referrer = request.value(forHTTPHeaderField: "Referer") {
            replay.setValue(referrer, forHTTPHeaderField: "Referer")
        }
        let linkID = UUID()
        stagedLinks[linkID] = StagedLink(
            request: replay, sourcePageID: page.id, dataStore: page.webView.configuration.websiteDataStore,
            stagedAt: now)
        return BrowserEngineNavigation(
            implementation: integration.implementationId, linkID: linkID, sourcePageID: page.id)
    }

    /// Asks the core to make the link `navigation` names the first load of
    /// `page`, when it loads `url`. False, forgetting the link, when it no
    /// longer applies: it is gone, heads elsewhere, was followed in another
    /// store, or the page has loaded something; or when the core refuses it.
    func stage(_ navigation: BrowserEngineNavigation, into page: WebKitEnginePage, expecting url: URL) -> Bool {
        guard navigation.implementation == integration.implementationId else { return false }
        let linkID = navigation.linkID
        guard let link = stagedLinks[linkID], link.request.url == url,
            link.dataStore === page.webView.configuration.websiteDataStore, page.webView.url == nil, let core
        else {
            stagedLinks[linkID] = nil
            return false
        }
        do {
            try core.send(
                StageLink(
                    pageID: page.id, sourcePageID: link.sourcePageID, stagedLinkID: linkID, url: url.absoluteString))
            return true
        } catch {
            stagedLinks[linkID] = nil
            return false
        }
    }

    // MARK: - Actions - Offered pages

    /// Offers the core `popup`, the page WebKit made for `opener`'s document
    /// to load `request`, as `PageOffered` from its opener, and answers the
    /// page the core adopted it as, or nil when the core refused it. The core
    /// decides where the page shows, and it runs on WebKit, its opener's
    /// engine; one the core keeps in the opener instead, as a Quick Window or
    /// Peek keeps what it opens, loads `request` there. A window asked for
    /// with no address heads to the empty document. A popup that wants a
    /// window of its own is offered as one, in
    /// its opener's Space, on the Mac, whose Quick Windows show it; iPhone and
    /// iPad show every popup as a tab. The core adopts or refuses it on this
    /// stack, while WebKit waits, and the changes it made are applied before
    /// this returns, so the page's owner hosts the page, and answers its
    /// navigations, before WebKit starts the first one.
    func offer(
        _ popup: WebKitPopup, from opener: WebKitEnginePage, for request: URLRequest, foreground: Bool
    ) -> WebKitEnginePage? {
        guard let engines else { return nil }
        let offerID = UUID()
        let source = engines.core.state.pages[opener.id]
        let space = source.flatMap { engines.core.state.workspaces[$0.workspaceID]?.spaces.model($0.spaceID) }
        // `window.open()` without a destination reaches WebKit as a request
        // with no URL, or an empty one.
        let url = request.url.map(\.absoluteString).flatMap { $0.isEmpty ? nil : $0 } ?? "about:blank"
        offers[offerID] = Offer(popup: popup, space: space, sourcePageID: opener.id, request: request)
        defer { offers[offerID] = nil }
        #if os(macOS)
            let window = popup.wantsWindow ? source?.spaceID : nil
        #else
            let window: UUID? = nil
        #endif
        report(
            PageOffered(
                offerID: offerID, profileID: opener.profileID, sourcePageID: opener.id, windowID: nil, spaceID: window,
                url: url, foreground: foreground))
        guard let page = adoptedOffers.removeValue(forKey: offerID) else {
            DiagnosticLog.popups.notice(
                "The core gave the window page \(opener.id) asked for no page of its own "
                    + "(window: \(popup.wantsWindow))")
            return nil
        }
        engines.core.drain()
        return page
    }

    // MARK: - Actions - Pages

    /// Keeps `page` as the binding's own, which its questions and its direct
    /// path reach while its owner keeps it.
    func keep(_ page: WebKitEnginePage) -> WebKitEnginePage {
        page.binding = self
        pages = pages.filter { $0.value.value != nil }
        pages[page.id] = WeakPage(value: page)
        return page
    }

    /// The page for `creation` in `space`: a popup's with the configuration
    /// WebKit derived from its opener's, as `popup` gives it, and any other's
    /// assembled for its profile's store and its Space's content rules with
    /// the platform's own settings, telling the binding when its media starts
    /// or stops. A page the core asked to bring back restores what it kept
    /// once its host attaches.
    func build(_ creation: CreatePage, in space: SpaceModel?, popup: WebKitPopup?) -> WebKitEnginePage {
        let contentRuleLists =
            space.map { contentRules.ruleLists(for: $0.settings.browsingPreferences.contentBlocking) }
            ?? []
        let configuration =
            popup?.configuration
            ?? BrowserPageConfiguration.make(
                for: BrowsingProfile(id: creation.profileID),
                websiteDataStore: store(for: creation),
                contentRuleLists: contentRuleLists,
                preferredContentMode: BrowserPlatformWebKit.preferredContentMode,
                decorate: BrowserPlatformWebKit.decorate)
        if popup == nil {
            // A popup shares its opener's controller, whose bridge already
            // runs in it and posts through the opener's handler.
            _ = WebKitMediaActivityBridge.install(in: configuration.userContentController) { [weak self] message in
                self?.mediaActivityMayHaveChanged(in: message.webView)
            }
        }
        return WebKitEnginePage(
            id: creation.pageID,
            profileID: creation.profileID,
            webView: BrowserPlatformWebKit.makeWebView(configuration: configuration),
            contentRuleLists: contentRuleLists,
            ownsUserContentController: popup == nil,
            isPrivate: creation.isPrivate,
            restoring: creation.restoreState)
    }

    /// Media in the page whose web view is `webView` started or stopped, so
    /// its host asks WebKit what the page runs now.
    private func mediaActivityMayHaveChanged(in webView: WKWebView?) {
        guard let webView, let page = pages.values.lazy.compactMap(\.value).first(where: { $0.webView === webView })
        else { return }
        page.host?.mediaActivityMayHaveChanged()
    }

    /// The website data store the page `creation` asks for browses in: its
    /// profile's store in memory when the page is private or the launch keeps
    /// nothing on disk, made the first time a page of the profile asks for
    /// it; otherwise the profile's store on disk, which its pages share while
    /// one holds it.
    private func store(for creation: CreatePage) -> WKWebsiteDataStore {
        let profileID = creation.profileID
        if creation.isPrivate || keepsProfilesInMemory {
            if let store = memoryStores[profileID] { return store }
            let store = WKWebsiteDataStore.nonPersistent()
            memoryStores[profileID] = store
            return store
        }
        liveStores = liveStores.filter { $0.value.value != nil }
        if let store = liveStores[profileID]?.value { return store }
        let store = BrowserWebsiteDataStore.persistent(for: BrowsingProfile(id: profileID))
        liveStores[profileID] = WeakStore(value: store)
        return store
    }

    // MARK: - Actions - Data

    /// The store the profile's pages use now, or for one that keeps nothing
    /// in memory only, its store on disk once looked up, when it has one.
    /// Never creates a store the profile does not have.
    func existingStore(for profileID: UUID, ephemeral: Bool) -> () async -> WKWebsiteDataStore? {
        let live = memoryStores[profileID] ?? liveStores[profileID]?.value
        let looksOnDisk = live == nil && !ephemeral && !keepsProfilesInMemory
        return {
            if let live { return live }
            return looksOnDisk ? await Self.storeOnDisk(for: profileID) : nil
        }
    }

    /// The profile's store on disk, when it has one.
    static func storeOnDisk(for profileID: UUID) async -> WKWebsiteDataStore? {
        let identifier = BrowserLaunchEnvironment.current.websiteDataStoreIdentifier(forProfileID: profileID)
        guard await WKWebsiteDataStore.allDataStoreIdentifiers.contains(identifier) else { return nil }
        return WKWebsiteDataStore(forIdentifier: identifier)
    }

    // MARK: - Actions - Prompts

    /// Raises with the core a script dialog the document of page `pageID`
    /// opened. The core settles it with the person's answer, or declines it
    /// when nobody can give one.
    func raise(_ question: ScriptDialogQuestion, for pageID: UUID, answer: @escaping @MainActor (Bool, String?) -> Void)
    {
        guard let engines else { return answer(false, nil) }
        let promptID = UUID()
        prompts[promptID] = WebKitPendingScriptDialog(pageID: pageID, answer: answer)
        engines.report(ScriptDialogOpened(promptID: promptID, pageID: pageID, question: question), from: self)
    }

    /// Raises with the core a server's request for a user name and password
    /// a load of page `pageID` met. The core settles it with the credential
    /// to answer with, or declines it.
    func raise(
        _ question: AuthenticationQuestion, for pageID: UUID,
        answer: @escaping @MainActor (AuthenticationCredential?) -> Void
    ) {
        guard let engines else { return answer(nil) }
        let promptID = UUID()
        prompts[promptID] = WebKitPendingAuthentication(pageID: pageID, answer: answer)
        engines.report(AuthenticationChallenged(promptID: promptID, pageID: pageID, question: question), from: self)
    }

    /// Raises with the core, as `promptID`, a site's request in page `pageID`
    /// for a capability. The core answers it from the Space's choices, or
    /// settles it with the person's answer.
    func raise(
        _ question: PermissionQuestion, for pageID: UUID, promptID: UUID = UUID(),
        answer: @escaping @MainActor (Bool) -> Void
    ) {
        guard let engines else { return answer(false) }
        prompts[promptID] = WebKitPendingPermission(pageID: pageID, answer: answer)
        engines.report(PermissionRequested(promptID: promptID, pageID: pageID, question: question), from: self)
    }

    /// Takes back a question a page no longer asks: WebKit hears it declined,
    /// and the core stops waiting for it and records nothing.
    func withdraw(_ promptID: UUID) {
        guard let prompt = prompts.removeValue(forKey: promptID) else { return }
        prompt.decline()
        engines?.report(PromptWithdrawn(promptID: promptID), from: self)
    }

    /// Shows one of this binding's prompts with `show` on the host of page
    /// `pageID`, or declines it when no host can show it.
    private func present(
        _ promptID: UUID, on pageID: UUID, _ show: (any BrowserPromptPresenting, BrowserPromptDismissal) -> Void
    ) {
        guard let prompt = prompts[promptID] else { return }
        guard let presenter = pages[pageID]?.value?.host else {
            _ = try? engines?.core.send(prompt.declining(promptID))
            return
        }
        show(presenter, dismissal(for: promptID))
    }

    /// A new dismissal for a question a page's host shows.
    private func dismissal(for promptID: UUID) -> BrowserPromptDismissal {
        let dismissal = BrowserPromptDismissal()
        dismissals[promptID] = dismissal
        return dismissal
    }

    /// Declines what page `pageID` still asks, which closes with it.
    func declinePrompts(of pageID: UUID) {
        for (promptID, prompt) in prompts where prompt.pageID == pageID {
            prompts[promptID] = nil
            prompt.decline()
        }
    }
}

/// Shows a question the core asks about one of this binding's pages on the
/// page's host, and closes it once the core settles it. One no host can show
/// is declined.
extension WebKitEngineBinding: CorePromptHost {
    func ask(_ asked: ScriptDialogAsked) {
        present(asked.promptID, on: asked.pageID) { $0.ask(asked, dismissal: $1) }
    }

    func ask(_ asked: AuthenticationAsked) {
        present(asked.promptID, on: asked.pageID) { $0.ask(asked, dismissal: $1) }
    }

    func ask(_ asked: PermissionAsked) {
        present(asked.promptID, on: asked.pageID) { $0.ask(asked, dismissal: $1) }
    }

    /// The Chromium engine reviews extension installs; WebKit has none.
    func ask(_ asked: ExtensionInstallAsked) {}

    /// The download prompts choose where a download goes.
    func ask(_ asked: DownloadDestinationAsked) {}

    /// The download prompts ask whether a download may go ahead.
    func ask(_ asked: DownloadApprovalAsked) {}

    /// The quit preparation asks about downloads in progress.
    func ask(_ asked: QuitWithDownloadsAsked) {}

    func dismiss(_ settled: PromptSettled) {
        dismissals.removeValue(forKey: settled.promptID)?.dismiss()
    }
}

extension Engines {
    /// WebKit's binding, when the composition registered it.
    var webKit: WebKitEngineBinding? { bindings[.webKit] as? WebKitEngineBinding }
}
