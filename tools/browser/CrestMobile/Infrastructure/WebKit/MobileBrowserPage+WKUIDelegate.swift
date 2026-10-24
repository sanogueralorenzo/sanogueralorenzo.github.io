import Dispatch
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

extension MobileBrowserPage: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor (UIContextMenuConfiguration?) -> Void
    ) {
        contextMenuPreviewCommit = nil
        guard webView === self.webView,
            let context = navigationContext,
            let url = elementInfo.linkURL,
            ExternalWebLink.accepts(url),
            let window = webView.window
        else {
            // WebKit supplies image and detected-data previews and their actions.
            completionHandler(nil)
            return
        }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID, profileID: context.assignment.profileID
        )
        let generation = committedNavigationCount
        let isCurrent: () -> Bool = { [weak self, weak window] in
            guard let self, let window else { return false }
            return self.webView.window === window
                && self.committedNavigationCount == generation
                && self.navigationContext?.tabID == source.tabID
                && self.navigationContext?.assignment
                    == BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)
                && self.linkDestinationHost.browser?.shownTab?.id == source.tabID
                && self.linkDestinationHost.canOpenLink(from: source)
        }
        let open: (BrowserSpaceRuntimeAssignment) -> Void = { [weak self] destination in
            guard isCurrent(), let self else { return }
            self.linkDestinationHost.openLink(url, from: source, in: destination)
        }
        let currentSpace = BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)
        contextMenuPreviewCommit = { open(currentSpace) }
        completionHandler(
            UIContextMenuConfiguration(
                identifier: nil,
                previewProvider: { [weak self] in
                    guard isCurrent(), let self else { return nil }
                    return MobileBrowserLinkPreviewController(
                        url: url, source: self.webView, isCurrent: isCurrent
                    )
                }
            ) { [weak self] suggested in
                guard let self, isCurrent(),
                    let space = linkDestinationHost.browser?.spaceModel(source.spaceID)
                else { return UIMenu(children: suggested) }
                @MainActor func icon(for space: SpaceModel) -> UIImage? {
                    let renderer = ImageRenderer(content: BrowserSpaceIdentityIcon(space: space))
                    renderer.scale = window.traitCollection.displayScale
                    return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
                }
                let current = UIAction(
                    title: String(localized: "Open in Current Space"), image: icon(for: space)
                ) { _ in
                    open(currentSpace)
                }
                var actions: [UIMenuElement] = [current]
                let spaces = linkDestinationHost.otherSpaces(from: source)
                if !spaces.isEmpty {
                    actions.append(
                        UIMenu(
                            title: String(localized: "Open in Other Space"),
                            image: UIImage(systemName: "square.stack"),
                            children: spaces.map { space in
                                UIAction(title: space.settings.name, image: icon(for: space)) { _ in
                                    open(BrowserSpaceRuntimeAssignment(space: space))
                                }
                            }
                        ))
                }
                return UIMenu(children: [UIMenu(options: .displayInline, children: actions)] + suggested)
            })
    }

    func webView(
        _ webView: WKWebView,
        contextMenuForElement elementInfo: WKContextMenuElementInfo,
        willCommitWithAnimator animator: any UIContextMenuInteractionCommitAnimating
    ) {
        guard webView === self.webView, let commit = contextMenuPreviewCommit else { return }
        animator.addCompletion(commit)
    }

    func webView(_ webView: WKWebView, contextMenuDidEndForElement elementInfo: WKContextMenuElementInfo) {
        contextMenuPreviewCommit = nil
    }

    /// Returns the popup's web view built from WebKit's own configuration, which
    /// is what keeps `window.open()` non-null, `window.opener` connected, and
    /// `about:blank` popups writable. The page offers the popup to the core,
    /// which decides where it shows; Crest never loads that web view itself:
    /// WebKit drives the navigation it already scheduled. A popup the core
    /// refuses gets no window, and never a tab of its own.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        recordAcceptedPopup()
        let foreground = corePage.selectsOpenedWindow(gesture: navigationAction.linkGesture)
        let webKitPage = webKitPage
        let request = navigationAction.request
        return popupCoordinator.resolveOpen(for: navigationAction, currentURL: webView.url) { _ in
            webKitPage.offer(WebKitPopup(configuration: configuration), for: request, foreground: foreground)?.webView
        }
    }

    /// WebKit reports native picture-in-picture only to the UI delegate. The
    /// page's residency reads it back through its engine.
    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange isActive: Bool) {
        webKitEngine?.hasVideoInPictureInPicture = isActive
        refreshMediaActivity()
    }

    /// The page's script asked to close its window, as `window.close()` does,
    /// once its document agreed to go. The core decides, as it does for every
    /// engine: only a page another page opened closes what owns it.
    func webViewDidClose(_ webView: WKWebView) {
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
    /// page shows once the core asks the person.
    private func askScriptDialog(
        _ kind: JavaScriptDialogKind, message: String, defaultText: String?, frame: WKFrameInfo,
        answer: @escaping @MainActor (Bool, String?) -> Void
    ) {
        webKitPage.ask(
            ScriptDialogQuestion(
                kind: kind, message: message, defaultText: defaultText ?? "",
                sourceURL: frame.request.url?.absoluteString ?? ""),
            answer: answer)
    }

    // Leave runOpenPanelWith unimplemented on iOS. WebKit's native upload flow
    // offers Photos, camera and Files using the input's accept/capture/multiple
    // attributes, owns presentation for this web view, and retains upload copies
    // for the content view's lifetime. A custom delegate replaces that entire flow.

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard webView === self.webView,
            let topLevelOrigin = webView.url.flatMap(SiteOrigin.init(url:))
        else {
            decisionHandler(.deny)
            return
        }
        answerPermission(
            SitePermission(type), origin: SiteOrigin(origin), topLevelOrigin: topLevelOrigin, from: webKitPage,
            decisionHandler: decisionHandler)
    }

    @available(iOS 27.0, *)
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
            .location, origin: SiteOrigin(origin), topLevelOrigin: topLevelOrigin, from: webKitPage,
            decisionHandler: decisionHandler)
    }
}
