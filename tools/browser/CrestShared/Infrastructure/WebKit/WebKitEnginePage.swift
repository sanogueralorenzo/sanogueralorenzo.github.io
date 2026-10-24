import WebKit

/// A page WebKit's binding built for a page the core opened: its web view,
/// built for the page's profile with the platform's own settings, and WebKit's
/// page port over it. The page's owner hosts the web view and answers its
/// delegates; the binding runs the core's loads in it, brings back the history
/// the core handed it, and keeps what brings it back when the core closes it
/// keeping its state.
@MainActor
final class WebKitEnginePage: EngineHostedPage {
    // MARK: - Variables

    /// The core's page this one is.
    let id: UUID
    /// The profile the page browses in, which its downloads belong to.
    let profileID: UUID
    let webView: WKWebView
    let engine: BrowserWebKitPageEngine
    /// The content rules the page was built with.
    let contentRuleLists: [WKContentRuleList]
    /// False when the page shares the user content controller of the page its
    /// configuration came from, which every popup does: WebKit copies the
    /// opener's configuration and the copy keeps the same controller.
    /// Installing the same script message handler twice on it throws, and
    /// removing one would strip it from the opener.
    let ownsUserContentController: Bool
    /// Whether the page browses in private, keeping nothing once it closes.
    let isPrivate: Bool
    /// The platform's page hosting this one, which shows the person the
    /// core's questions about it and gets ready for the loads the binding
    /// runs in it.
    private(set) weak var host: (any WebKitPageHosting)?
    /// The binding that built the page, which raises its questions with the
    /// core.
    weak var binding: WebKitEngineBinding?
    /// What an earlier page of the page's tab kept, which the core handed the
    /// binding to bring back once the page's host attaches.
    private var restoring: PageRestoreState?

    /// The platform's direct path to the page: going back, reloading, zooming,
    /// finding text and keeping its history.
    func makeEnginePage() -> EnginePage {
        guard let pages = binding?.enginePages else {
            preconditionFailure("A WebKit page came without the binding that built it.")
        }
        return EnginePage(
            id: id, pages: pages, historyFamily: .webKit, historyVersion: { BrowserTabStateEnvelope.currentOSBuild },
            inspectorPanels: Set(InspectorPanel.allCases))
    }

    // MARK: - Initializers

    init(
        id: UUID, profileID: UUID, webView: WKWebView, contentRuleLists: [WKContentRuleList],
        ownsUserContentController: Bool, isPrivate: Bool = false, restoring: PageRestoreState? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.webView = webView
        engine = BrowserWebKitPageEngine(webView: webView)
        self.contentRuleLists = contentRuleLists
        self.ownsUserContentController = ownsUserContentController
        self.isPrivate = isPrivate
        self.restoring = restoring
        engine.enginePage = self
    }

    // MARK: - Actions - Hosting

    /// Gives the page to `host`, once it is ready to hear the page's
    /// navigations. A page the core asked to bring back restores its history
    /// now, in place of its first load, and loads the address it kept when
    /// WebKit refuses that history.
    func attach(_ host: any WebKitPageHosting) {
        self.host = host
        guard let restoring else { return }
        self.restoring = nil
        guard let url = URL(string: restoring.url) else { return }
        host.prepareToLoad(url)
        if !engine.restoreHistory(restoring.state) { engine.load(URLRequest(url: url)) }
    }

    // MARK: - Actions - Navigation

    /// Loads `url` as the app's own load, once the page's host is ready for it.
    func load(_ url: URL) {
        load(URLRequest(url: url))
    }

    /// Loads `request` as `load(_:)` does, keeping its method, body and
    /// headers, such as the referrer of a window the page's document asked
    /// for, which the core kept in this page.
    func load(_ request: URLRequest) {
        if let url = request.url { host?.prepareToLoad(url) }
        engine.load(request)
    }

    // MARK: - Actions - Links

    /// What a person's activation of the link to `url` in the page does, as
    /// the core decides from the page's tab, how a page without one presents,
    /// `gesture` and this device's link preferences. A link with no address
    /// loads in the page. A page no binding holds lets a person's own
    /// top-level click open a new tab, so a pinned or saved tab never leaves
    /// the page it keeps.
    func linkActivation(to url: URL?, gesture: LinkGesture) -> LinkNavigationDecision {
        guard let url else { return .navigate }
        guard let answer = binding?.ask(LinkActivation(pageID: id, url: url.absoluteString, gesture: gesture)) else {
            return gesture.userActivated && gesture.topLevel ? .foregroundTab : .navigate
        }
        return answer.decision
    }

    /// Stages `request`, a modified link the page followed, for the Peek the
    /// core opens for it; nil for a link that cannot be staged.
    func stageLink(_ request: URLRequest) -> BrowserEngineNavigation? {
        binding?.stageLink(request, from: self)
    }

    /// Makes the link `navigation` names this page's first load, when it
    /// loads `url`; false when it no longer applies or the core refuses it.
    func stage(_ navigation: BrowserEngineNavigation, expecting url: URL) -> Bool {
        binding?.stage(navigation, into: self, expecting: url) ?? false
    }

    /// Offers the core `popup`, the page WebKit made for this page's
    /// document to load `request`, and answers the page the core adopted it
    /// as, which its owner already hosts, or nil when the core refused it or
    /// kept it in this page. The core decides where it shows; it runs on
    /// WebKit, as its opener does.
    func offer(_ popup: WebKitPopup, for request: URLRequest, foreground: Bool) -> WebKitEnginePage? {
        binding?.offer(popup, from: self, for: request, foreground: foreground)
    }

    /// What brings the page back as it is: WebKit's history, at the address
    /// the page shows. A popup and a private page keep nothing, and neither
    /// does a page that never committed a document.
    var restoreState: PageRestoreState? {
        guard ownsUserContentController, !isPrivate, let url = webView.url, let state = engine.savedHistory()
        else { return nil }
        return PageRestoreState(url: url.absoluteString, state: state)
    }

    // MARK: - Actions - Prompts

    /// Asks the core the script dialog the page's document opened. `answer`
    /// runs once: with the person's answer, or declined when nobody can give
    /// one.
    func ask(_ question: ScriptDialogQuestion, answer: @escaping @MainActor (Bool, String?) -> Void) {
        guard let binding else { return answer(false, nil) }
        binding.raise(question, for: id, answer: answer)
    }

    /// Asks the core a server's request for a user name and password. `answer`
    /// runs once: with the credential to answer the server with, or nil.
    func ask(_ question: AuthenticationQuestion, answer: @escaping @MainActor (AuthenticationCredential?) -> Void) {
        guard let binding else { return answer(nil) }
        binding.raise(question, for: id, answer: answer)
    }

    /// Asks the core a site's request for a capability. `answer` runs once:
    /// whether the site may use it.
    func ask(_ question: PermissionQuestion, answer: @escaping @MainActor (Bool) -> Void) {
        guard let binding else { return answer(false) }
        binding.raise(question, for: id, answer: answer)
    }

    /// Asks the core a site's request for a capability, and answers whether
    /// the site may use it. A caller that stops waiting withdraws the
    /// question, so the core records no answer the person gives it later.
    func ask(_ question: PermissionQuestion) async -> Bool {
        guard let binding else { return false }
        let promptID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                binding.raise(question, for: id, promptID: promptID) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            Task { @MainActor in binding.withdraw(promptID) }
        }
    }

    // MARK: - Actions - Downloads

    /// Hands the core a download the page's web view started, which the
    /// binding runs as WebKit's own. `isUserInitiated` counts it as the
    /// person's when a trusted gesture of theirs started it.
    func startDownload(_ download: WKDownload, isUserInitiated: Bool = false) {
        guard let binding else {
            download.cancel { _ in }
            return
        }
        binding.downloads.start(download, from: self, isUserInitiated: isUserInitiated)
    }

    /// Starts a new automatic-download sequence for the page, whose document
    /// was replaced or which goes away.
    func resetAutomaticDownloads() {
        binding?.downloads.resetAutomaticSequence(of: id)
    }
}
