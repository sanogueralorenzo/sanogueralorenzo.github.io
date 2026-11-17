import AppKit
import WebKit

extension BrowserPage {
    func updateEditProtection() {
        hasUnsavedEdits = documentHasEdits || frameEdits.values.contains(true)
    }

    func checkpointNativeState() {
        guard let owner, owner.pages[id] === self, let (s, t) = owner.tabIndex(id) else { return }
        owner.session.spaces[s].tabs[t].zoom = webView.pageZoom
        guard webView.backForwardList.currentItem != nil else { return }
        if let data = webView.interactionState as? Data, data.count <= 8 * 1_024 * 1_024 {
            owner.session.spaces[s].tabs[t].interactionState = data
        }
    }

    func restore(_ tab: BrowserTab) {
        guard !isRetired else { return }
        restoreState = tab.documentState
        webView.pageZoom = tab.zoom
        if let url = tab.url { load(url, restoring: tab.interactionState) }
    }

    func captureDocumentState() async {
        guard let owner, owner.pages[id] === self, owner.tabIndex(id) != nil,
            !isLoading, let expected = webView.url
        else { return }
        let generation = documentRevision
        let script = #"""
            const selector = e => {
              if(e.id && document.querySelectorAll('#'+CSS.escape(e.id)).length === 1) return '#'+CSS.escape(e.id);
              let parts = [], n = e;
              while(n && n !== document.body && parts.length < 12) {
                const peers = [...(n.parentElement?.children || [])].filter(v => v.tagName === n.tagName);
                parts.unshift(n.tagName.toLowerCase()+':nth-of-type('+(peers.indexOf(n)+1)+')'); n = n.parentElement;
              }
              return 'body > '+parts.join(' > ');
            };
            const sensitive = e => /password|file|hidden/.test(e.type) || /password|secret|token|cvv|cvc/i.test(e.name || '')
              || /cc-|one-time-code|current-password|new-password/.test(e.autocomplete || '');
            const fields = [...document.querySelectorAll('input,textarea,select')].filter(e => !sensitive(e)).slice(0,200)
              .map(e => ({selector:selector(e),value:String(e.value || '').slice(0,8192),
                          checked:['checkbox','radio'].includes(e.type) ? e.checked : null}));
            return JSON.stringify({url:location.href,x:scrollX,y:scrollY,fields});
            """#
        guard
            let json = try? await webView.callAsyncJavaScript(
                script, arguments: [:], in: nil, contentWorld: .defaultClient) as? String,
            json.utf8.count <= 1_024 * 1_024, generation == documentRevision, expected == webView.url,
            let data = json.data(using: .utf8),
            let state = try? JSONDecoder().decode(BrowserDocumentState.self, from: data),
            owner.pages[id] === self, let (s, t) = owner.tabIndex(id), owner.session.spaces[s].id == spaceID
        else { return }
        if owner.session.spaces[s].tabs[t].documentState != state {
            owner.session.spaces[s].tabs[t].documentState = state
            checkpointNativeState()
            owner.changed()
        }
    }

    func restoreDocumentState() async {
        guard let state = restoreState, state.url == webView.url?.absoluteString else {
            restoreState = nil
            return
        }
        restoreState = nil
        let script = #"""
            const s = JSON.parse(state);
            if(s.url !== location.href) return false;
            for(const f of s.fields) {
              const e = document.querySelector(f.selector); if(!e || ['password','file','hidden'].includes(e.type)) continue;
              e.value = f.value; if(f.checked !== null) e.checked = f.checked;
            }
            scrollTo(s.x,s.y); return true;
            """#
        guard let data = try? JSONEncoder().encode(state), let json = String(data: data, encoding: .utf8) else {
            return
        }
        _ = try? await webView.callAsyncJavaScript(
            script, arguments: ["state": json], in: nil, contentWorld: .defaultClient)
    }

    func prepareToClose(automatically: Bool = false) async -> Bool {
        guard closeContinuation == nil else { return false }
        automaticClose = automatically
        let selector = NSSelectorFromString("_tryClose")
        if !webView.responds(to: selector) {
            await refreshPageState()
            guard !automatically else { return false }
            if hasUnsavedEdits {
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

    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange active: Bool) {
        hasPictureInPicture = active
        pictureInPicture?.nativePresentationDidChange(isActive: active)
    }

    func refreshReaderAvailability() async {
        readerAvailable =
            (try? await webView.callAsyncJavaScript(
                BrowserReaderModeJavaScriptBridge.source,
                arguments: ["action": "availability"], in: nil, contentWorld: .defaultClient) as? Bool) ?? false
    }

    func toggleReader() {
        let action = isReaderMode ? "deactivate" : "activate"
        Task {
            if (try? await webView.callAsyncJavaScript(
                BrowserReaderModeJavaScriptBridge.source,
                arguments: ["action": action, "readerModeLabel": "Reader Mode"], in: nil, contentWorld: .defaultClient)
                as? Bool) == true
            {
                isReaderMode.toggle()
            }
        }
    }
}

extension BrowserPage {
    func showDeveloperTools() {
        let selector = NSSelectorFromString("_inspector")
        guard webView.responds(to: selector),
            let inspector = webView.perform(selector)?.takeUnretainedValue() as? NSObject,
            inspector.responds(to: NSSelectorFromString("show"))
        else {
            owner?.showNotice("Use Inspect Element in the page's context menu.")
            return
        }
        inspector.perform(NSSelectorFromString("show"))
    }
}
