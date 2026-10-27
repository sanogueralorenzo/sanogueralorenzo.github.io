import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserPage: NSObject, WKNavigationDelegate, WKUIDelegate, Identifiable {
    // MARK: - Variables

    let id: UUID
    let spaceID: UUID
    let webView: WKWebView
    var title = ""
    var url: URL?
    var favicon: Data?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var progress = 0.0
    var failure: String?
    var isPlaying = false
    var mediaTitle = ""
    var hasUnsavedEdits = true
    @ObservationIgnored var documentHasEdits = true
    var lastSelected = Date()
    var translationRequest = 0
    var documentRevision = 0
    var frameEdits: [String: Bool] = [:]
    @ObservationIgnored var pendingNavigationURL: URL?
    var hasPictureInPicture = false
    @ObservationIgnored var pictureInPicture: BrowserPictureInPicturePageController?
    var isReaderMode = false
    var readerAvailable = false
    var mediaArtist = ""
    var mediaDuration = 0.0
    var mediaElapsed = 0.0
    @ObservationIgnored var mediaFrame: WKFrameInfo?
    var hostingWindowID: UUID?
    var mirrorImage: NSImage?
    var isSharedAcrossWindows: Bool {
        (owner?.owner.contexts.values.filter { !$0.isClosed && $0.visiblePages.contains(where: { $0.id == id }) }.count
            ?? 0) > 1
    }
    var scriptMayClose = false
    var isProtectedFromUnloading: Bool {
        isPlaying || hasPictureInPicture || pictureInPicture?.protectsPageResidency == true || hasUnsavedEdits
            || webView.cameraCaptureState != .none
            || webView.microphoneCaptureState != .none
            || (webView as? BrowserNativeWebView)?.displayCaptureActive == true || closeContinuation != nil
    }
    @ObservationIgnored var closeContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored var closeTask: Task<Void, Never>?
    @ObservationIgnored var automaticClose = false
    @ObservationIgnored var restoreState: BrowserDocumentState?
    @ObservationIgnored var siteController: BrowserSiteController?
    @ObservationIgnored var uploadScopes: [URL] = []
    @ObservationIgnored weak var owner: BrowserStore?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var blockingTask: Task<Void, Never>?
    @ObservationIgnored private var isRetired = false
    @ObservationIgnored private var readingMedia = false
    @ObservationIgnored private var loadGeneration = UUID()

    // MARK: - Initializers

    init(id: UUID, spaceID: UUID, configuration: WKWebViewConfiguration, owner: BrowserStore) {
        self.id = id
        self.spaceID = spaceID
        self.owner = owner
        // Popup configurations share process/data stores with their opener, but handlers belong to one document host.
        configuration.userContentController = WKUserContentController()
        if owner.preferences.blocksContent, let rules = BrowserContentBlocking.shared.ready {
            configuration.userContentController.add(rules)
        }
        owner.configureWebKit(configuration.preferences)
        BrowserDesktopPictureInPictureAccess.enable(in: configuration.preferences)
        BrowserPictureInPictureContentBridge.shared.install(in: configuration.userContentController)
        webView = BrowserNativeWebView(frame: .zero, configuration: configuration)
        super.init()
        (webView as? BrowserNativeWebView)?.page = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.synchronize() }
            },
        ]
        pictureInPicture = BrowserPictureInPicturePageController(webView: webView)
        pictureInPicture?.residencyProtectionChanged = { [weak self] in
            guard let self else { return }
            hasPictureInPicture = pictureInPicture?.isPictureInPictureActive == true
        }
        siteController = BrowserSiteController(page: self)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.mediaActionScript,
                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        applyContentBlocking()
    }

    // MARK: - Actions - Browsing

    func load(_ url: URL) {
        failure = nil
        pendingNavigationURL = url
        self.url = url
        owner?.pageChanged(self)
        let generation = UUID()
        loadGeneration = generation
        Task { [weak self] in
            await self?.blockingTask?.value
            guard let self, !isRetired, loadGeneration == generation else { return }
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
        }
    }

    func waitForContentBlocking() async { await blockingTask?.value }

    func applyContentBlocking() {
        blockingTask?.cancel()
        guard owner?.preferences.blocksContent == true else {
            webView.configuration.userContentController.removeAllContentRuleLists()
            return
        }
        blockingTask = Task { [weak self] in
            do {
                let rules = try await BrowserContentBlocking.shared.rules()
                guard let self, !Task.isCancelled, !isRetired else { return }
                webView.configuration.userContentController.removeAllContentRuleLists()
                webView.configuration.userContentController.add(rules)
            } catch {
                guard !Task.isCancelled else { return }
                self?.owner?.showNotice("Content blocking could not load: " + error.localizedDescription)
            }
        }
    }

    func invalidate() {
        isRetired = true
        blockingTask?.cancel()
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        pictureInPicture?.invalidate()
        siteController?.invalidate()
        for scope in uploadScopes { scope.stopAccessingSecurityScopedResource() }
        uploadScopes.removeAll()
        finishClose(false)
        owner = nil
    }

    private func synchronize() {
        guard !isRetired else { return }
        title = String((webView.title ?? "").prefix(2048))
        url = pendingNavigationURL ?? webView.url
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        owner?.pageChanged(self)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failure = nil
        (webView as? BrowserNativeWebView)?.contextSelection = ""
        siteController?.navigationStarted()
        frameEdits.removeAll()
        isReaderMode = false
        hasUnsavedEdits = true
        documentHasEdits = true
        documentRevision &+= 1
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pendingNavigationURL = nil
        synchronize()
        pictureInPicture?.navigationDidCommit()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pendingNavigationURL = nil
        synchronize()
        owner?.pageFinished(self)
        checkpointNativeState()
        Task { [weak self] in
            await self?.restoreDocumentState()
            await self?.refreshReaderAvailability()
        }
        Task { [weak self] in
            await self?.captureFavicon()
            await self?.readMediaState()
            self?.captureMirror()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let value = error as NSError
        if value.code == NSURLErrorCancelled || (value.domain == "WebKitErrorDomain" && value.code == 102) {
            pendingNavigationURL = nil
            synchronize()
            return
        }
        failure = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let value = error as NSError
        if value.code == NSURLErrorCancelled || (value.domain == "WebKitErrorDomain" && value.code == 102) {
            pendingNavigationURL = nil
            synchronize()
            return
        }
        failure = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failure = "This page stopped. Reload to continue."
        isPlaying = false
        pictureInPicture?.invalidate()
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        let allowed = ["http", "https", "file", "about", "data", "blob", "javascript"]
        if !allowed.contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated || (scriptMayClose && action.targetFrame?.isMainFrame == true) {
                Task {
                    let alert = NSAlert()
                    alert.messageText = "Open an external application?"
                    alert.informativeText = "This link uses \(url.scheme ?? "an external") and will leave Lean."
                    alert.addButton(withTitle: "Cancel")
                    alert.addButton(withTitle: "Open")
                    if await BrowserDialogs.ask(alert, in: webView.window) == .alertSecondButtonReturn {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } else if url.isFileURL && action.sourceFrame.request.url?.isFileURL != true && self.url?.isFileURL != true {
            decisionHandler(.cancel)
        } else {
            if action.targetFrame?.isMainFrame == true && url.scheme != "javascript" {
                pendingNavigationURL = url
                self.url = url
                owner?.pageChanged(self)
            }
            decisionHandler(action.shouldPerformDownload ? .download : .allow)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        pendingNavigationURL = nil
        failure = nil
        synchronize()
        owner?.beginDownload(download, spaceID: spaceID)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        pendingNavigationURL = nil
        failure = nil
        synchronize()
        owner?.beginDownload(download, spaceID: spaceID)
    }

    func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let generation = documentRevision
        Task {
            let result = await BrowserAuthentication.answer(challenge, in: webView.window ?? owner?.window)
            guard generation == documentRevision, owner != nil else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(result.0, result.1)
        }
    }

    // MARK: - Actions - Native website UI

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let owner else { return nil }
        if navigationAction.request.url?.isFileURL == true
            && navigationAction.sourceFrame.request.url?.isFileURL != true
        {
            return nil
        }
        if let origin = BrowserSiteController.origin(navigationAction.sourceFrame.securityOrigin),
            owner.permission(.popups, origin: origin, spaceID: spaceID) == .deny
        {
            return nil
        }
        return owner.openPopup(configuration: configuration, url: navigationAction.request.url, spaceID: spaceID)
    }

    func webViewDidClose(_ webView: WKWebView) {
        if closeContinuation != nil { finishClose(true) } else if scriptMayClose { owner?.deleteTab(id) }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Website"
        alert.informativeText = String(message.prefix(4_000))
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Website"
        alert.informativeText = String(message.prefix(4_000))
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Website"
        alert.informativeText = String(prompt.prefix(4_000))
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) {
                if $0 == .OK {
                    for url in panel.urls {
                        if url.startAccessingSecurityScopedResource() { self.uploadScopes.append(url) }
                    }
                    completionHandler(panel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        } else {
            completionHandler(nil)
        }
    }

    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        Task { [weak self] in
            guard let self, let siteController else {
                decisionHandler(.deny)
                return
            }
            let generation = documentRevision
            guard webView === self.webView, frame.webView === webView,
                let name = BrowserSiteController.origin(origin)
            else {
                decisionHandler(.deny)
                return
            }
            let kinds: [BrowserSitePermission.Kind] =
                type == .camera ? [.camera] : type == .microphone ? [.microphone] : [.camera, .microphone]
            for kind in kinds {
                guard await siteController.decide(kind, origin: origin, frame: frame) else {
                    decisionHandler(.deny)
                    return
                }
            }
            guard generation == documentRevision,
                kinds.allSatisfy({ owner?.permission($0, origin: name, spaceID: spaceID) == .allow })
            else {
                decisionHandler(.deny)
                return
            }
            siteController.recordCapture(kinds, origin: name)
            decisionHandler(.grant)
        }
    }

    private func present(
        _ alert: NSAlert, completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        guard let window = webView.window ?? NSApp.mainWindow else {
            completion(.abort)
            return
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    // MARK: - Actions - Media and icons

    func readMediaState() async {
        guard !isRetired, !readingMedia else { return }
        readingMedia = true
        defer { readingMedia = false }
        let script = #"""
            const media = [...document.querySelectorAll('video,audio')].some(e => !e.paused && !e.ended);
            const dirty = [...document.querySelectorAll('input,textarea,select,[contenteditable=true]')].some(e =>
              (!e.isContentEditable && (e.type === 'checkbox' || e.type === 'radio' ? e.checked !== e.defaultChecked :
              e.tagName === 'SELECT' ? [...e.options].some(o => o.selected !== o.defaultSelected) : e.value !== e.defaultValue)));
            const e = document.querySelector('video,audio');
            return {playing:media, dirty, title:navigator.mediaSession?.metadata?.title || document.title,
              artist:navigator.mediaSession?.metadata?.artist || '', duration: Number.isFinite(e?.duration) ? e.duration : 0,
              elapsed:Number.isFinite(e?.currentTime) ? e.currentTime : 0};
            """#
        let revision = documentRevision
        guard
            var value = try? await webView.callAsyncJavaScript(
                script, arguments: [:], in: nil, contentWorld: .defaultClient)
                as? [String: Any], !isRetired
        else { return }
        var dirty = value["dirty"] as? Bool != false
        mediaFrame = nil
        if value["playing"] as? Bool != true {
            for frame in Array(siteController?.frames.values ?? [:].values).filter({ !$0.isMainFrame }).prefix(32) {
                guard
                    let child = try? await webView.callAsyncJavaScript(
                        script, arguments: [:], in: frame, contentWorld: .defaultClient) as? [String: Any],
                    revision == documentRevision
                else { continue }
                dirty = dirty || child["dirty"] as? Bool != false
                if child["playing"] as? Bool == true {
                    value = child
                    mediaFrame = frame
                    break
                }
            }
        }
        guard revision == documentRevision else { return }
        let native = await withCheckedContinuation { continuation in
            webView.requestMediaPlaybackState { continuation.resume(returning: $0) }
        }
        guard revision == documentRevision, !isRetired else { return }
        isPlaying = native == .playing || value["playing"] as? Bool == true
        documentHasEdits = dirty
        hasUnsavedEdits = documentHasEdits || frameEdits.values.contains(true)
        mediaTitle = value["title"] as? String ?? title
        mediaArtist = value["artist"] as? String ?? ""
        mediaDuration = value["duration"] as? Double ?? 0
        mediaElapsed = value["elapsed"] as? Double ?? 0
    }

    func toggleMedia() {
        performMediaAction(isPlaying ? "pause" : "play")
        Task { await readMediaState() }
    }

    func beginPictureInPicture() { pictureInPicture?.leaveTab() }

    func captureMirror() {
        guard isSharedAcrossWindows, webView.bounds.width > 0 else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in self?.mirrorImage = image }
    }

    private func captureFavicon() async {
        let script = #"""
            const link = document.querySelector('link[rel~="icon"]');
            const url = new URL(link?.href || '/favicon.ico', location.href);
            if(!['https:', 'http:'].includes(url.protocol)) return null;
            const response = await fetch(url, {credentials:'same-origin'});
            if(!response.ok) return null;
            const blob = await response.blob();
            if(blob.size > 32768) return null;
            return await new Promise(resolve => { const reader = new FileReader();
              reader.onload = () => resolve(reader.result); reader.readAsDataURL(blob); });
            """#
        let document = documentRevision
        guard
            let dataURL = try? await webView.callAsyncJavaScript(
                script, arguments: [:], in: nil, contentWorld: .defaultClient)
                as? String, !isRetired, document == documentRevision,
            let comma = dataURL.firstIndex(of: ","),
            let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
            NSImage(data: data) != nil
        else { return }
        favicon = data
        owner?.pageChanged(self)
    }
}
