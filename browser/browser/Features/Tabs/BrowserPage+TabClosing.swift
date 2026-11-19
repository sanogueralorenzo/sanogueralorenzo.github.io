import AppKit
import WebKit

extension BrowserPage {
    var isProtectedFromUnloading: Bool {
        isPlaying || hasPictureInPicture || pictureInPicture?.protectsPageResidency == true
            || documentActivity.hasUnsavedEdits
            || webView.cameraCaptureState != .none
            || webView.microphoneCaptureState != .none
            || (webView as? BrowserNativeWebView)?.displayCaptureActive == true || closeContinuation != nil
    }

    func prepareToClose(automatically: Bool = false) async -> Bool {
        guard closeContinuation == nil else { return false }
        automaticClose = automatically
        let selector = NSSelectorFromString("_tryClose")
        if !webView.responds(to: selector) {
            await refreshPageState()
            guard !automatically else { return false }
            if documentActivity.hasUnsavedEdits {
                let alert = NSAlert()
                alert.messageText = "Leave this page?"
                alert.informativeText = "Changes on this page may not be saved."
                alert.addButton(withTitle: "Stay")
                alert.addButton(withTitle: "Leave")
                return await BrowserDialogs.ask(alert, in: webView.window) == .alertSecondButtonReturn
            }
            return true
        }
        typealias TryClose = @convention(c) (AnyObject, Selector) -> Bool
        let action = unsafeBitCast(webView.method(for: selector), to: TryClose.self)
        return await withCheckedContinuation { continuation in
            closeContinuation = continuation
            if action(webView, selector) { finishClose(true) } else if closeContinuation != nil { startCloseTimeout() }
        }
    }

    func startCloseTimeout() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            self?.finishClose(false)
        }
    }

    func finishClose(_ allowed: Bool) {
        closeTask?.cancel()
        closeTask = nil
        automaticClose = false
        let completion = closeContinuation
        closeContinuation = nil
        completion?.resume(returning: allowed)
    }

    @objc(_webView:runBeforeUnloadConfirmPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(
        _ webView: WKWebView, runBeforeUnloadConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        closeTask?.cancel()
        if automaticClose {
            completionHandler(false)
            finishClose(false)
            return
        }
        Task {
            let alert = NSAlert()
            alert.messageText = "Leave this page?"
            alert.informativeText = "Changes on \(frame.securityOrigin.host) may not be saved."
            alert.addButton(withTitle: "Stay")
            alert.addButton(withTitle: "Leave")
            let allowed = await BrowserDialogs.ask(alert, in: webView.window) == .alertSecondButtonReturn
            completionHandler(allowed)
            if allowed && closeContinuation != nil { startCloseTimeout() } else { finishClose(false) }
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        if closeContinuation != nil { finishClose(true) } else if scriptMayClose { owner?.deleteTab(id) }
    }
}
