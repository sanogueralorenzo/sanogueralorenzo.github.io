import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit

extension BrowserPage: WKUIDelegate {
    /// The PDF HUD supplies its live document bytes through this desktop
    /// callback, rather than creating a WKDownload. Keep the supplied data:
    /// fetching the URL again can lose edits or an authenticated response.
    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    func webView(
        _ webView: WKWebView,
        saveDataToFile data: Data,
        suggestedFilename: String,
        mimeType: String,
        originatingURL: URL
    ) {
        guard webView === self.webKitView else { return }
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
        let feedbackSource = BrowserMacDownloadFeedbackSource.capture(in: webView)
        Task { [downloadCenter, spaceName] in
            await downloadCenter.saveData(
                data, suggestedFilename: suggestedFilename, mimeType: mimeType,
                originatingURL: originatingURL, assignment: assignment,
                spaceName: spaceName, feedbackSource: feedbackSource)
        }
    }

    /// WebKit's desktop presentation callback also covers entry from its own
    /// video context menu, including videos inside cross-origin frames.
    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange isActive: Bool) {
        pictureInPicture?.nativePresentationDidChange(isActive: isActive)
        webKitEngine?.hasVideoInPictureInPicture = isActive
        refreshMediaActivity()
    }

    /// WebKit offers beforeunload confirmation only through this desktop SPI;
    /// without it every dirty page would leave silently. It covers ordinary
    /// navigations as well as a close the page's engine asked to prepare.
    @objc(_webView:runBeforeUnloadConfirmPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(
        _ webView: WKWebView,
        runBeforeUnloadConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let engine = webKitEngine
        engine?.beforeUnloadPanelWillAppear()
        askScriptDialog(.beforeUnload, message: message, defaultText: nil, frame: frame) { leaving, _ in
            completionHandler(leaving)
            engine?.beforeUnloadPanelDidFinish(leaving: leaving)
        }
    }

    /// Native PiP's Restore action asks the embedder to reveal its document,
    /// and WebKit returns the video inline itself. The ordinary Close action
    /// does not send this callback. Fullscreen also uses it, so only a
    /// still-valid PiP source tells the core, which shows the page's tab.
    @objc(_webViewFullscreenMayReturnToInline:)
    func webViewFullscreenMayReturnToInline(_ webView: WKWebView) {
        guard webView === self.webKitView, pictureInPicture?.canRestoreSource == true else { return }
        corePage.report(PictureInPictureReturned(pageID: corePage.id))
    }

    /// Returns the popup's web view built from WebKit's own configuration, which
    /// is what keeps `window.open()` non-null, `window.opener` connected, and
    /// `about:blank` popups writable. The page offers the popup to the core,
    /// which decides where it shows, a Quick Window for one that asked for a
    /// window of its own and a tab beside this one otherwise, and keeps it on
    /// WebKit, this page's engine; Crest never loads that web view itself:
    /// WebKit drives the navigation it already scheduled. A popup the core
    /// refuses gets no window, and never a tab of its own.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        recordAcceptedPopup()
        let externalSchemeCoordinator = externalSchemeCoordinator
        let popups = BrowserPopupCoordinator(handOffExternalScheme: { destinationURL, trigger, origin in
            externalSchemeCoordinator.handOff(destinationURL: destinationURL, trigger: trigger, origin: origin)
        })
        let webKitPage = webKitAdapter?.webKitPage
        let foreground = corePage.selectsOpenedWindow(gesture: navigationAction.linkGesture)
        let popup = WebKitPopup(configuration: configuration, wantsWindow: windowFeatures.requestsPopupWindow)
        let request = navigationAction.request
        return popups.resolveOpen(for: navigationAction, currentURL: webView.url) { _ in
            webKitPage?.offer(popup, for: request, foreground: foreground)?.webView
        }
    }

    /// The page's script asked to close its window, as `window.close()` does,
    /// once its document agreed to go. The core decides, as it does for every
    /// engine: only a page another page opened closes what owns it.
    func webViewDidClose(_ webView: WKWebView) {
        // A close Crest prepared reports its approval here, not a script close.
        if webKitEngine?.webViewDidClose() == true { return }
        corePage.report(PageCloseRequested(pageID: corePage.id))
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        askScriptDialog(.alert, message: message, defaultText: nil, frame: frame) { _, _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        askScriptDialog(.confirm, message: message, defaultText: nil, frame: frame) { accepted, _ in
            completionHandler(accepted)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        askScriptDialog(.prompt, message: prompt, defaultText: defaultText, frame: frame) { accepted, text in
            completionHandler(accepted ? text ?? "" : nil)
        }
    }

    /// Asks the core the script dialog `frame`'s document opened, which this
    /// page shows once the core asks the person. A page WebKit's binding did
    /// not build has no one to ask, and declines.
    private func askScriptDialog(
        _ kind: JavaScriptDialogKind, message: String, defaultText: String?, frame: WKFrameInfo,
        answer: @escaping @MainActor (Bool, String?) -> Void
    ) {
        guard let webKitPage = webKitAdapter?.webKitPage else { return answer(false, nil) }
        webKitPage.ask(
            ScriptDialogQuestion(
                kind: kind, message: message, defaultText: defaultText ?? "",
                sourceURL: frame.request.url?.absoluteString ?? ""),
            answer: answer)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        dialogPresenter.presentFileInput(
            options: BrowserFileInputOptions(
                allowsDirectories: parameters.allowsDirectories,
                allowsMultipleSelection: parameters.allowsMultipleSelection
            ),
            request: frame.request,
            completion: { [weak self] urls in
                guard let self, let urls else {
                    completionHandler(nil)
                    return
                }
                do {
                    try self.fileUploadAccess.prepare(urls)
                    completionHandler(urls)
                } catch {
                    self.dialogPresenter.presentFileAccessFailure(
                        error,
                        request: frame.request
                    ) { completionHandler(nil) }
                }
            }
        )
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard webView === self.webKitView,
            let topLevelOrigin = webView.url.flatMap(SiteOrigin.init(url:))
        else {
            decisionHandler(.deny)
            return
        }
        answerPermission(
            SitePermission(type), origin: SiteOrigin(origin), topLevelOrigin: topLevelOrigin,
            from: webKitAdapter?.webKitPage,
            decisionHandler: decisionHandler)
    }

    @available(macOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard frame.webView === webView,
            let topLevelOrigin = webView.url.flatMap(SiteOrigin.init(url:))
        else {
            decisionHandler(.deny)
            return
        }
        answerPermission(
            .location, origin: SiteOrigin(origin), topLevelOrigin: topLevelOrigin, from: webKitAdapter?.webKitPage,
            decisionHandler: decisionHandler)
    }
}
