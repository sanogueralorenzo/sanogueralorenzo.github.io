import WebKit

struct BrowserDocumentState: Codable, Equatable, Sendable {
    struct Field: Codable, Equatable, Sendable {
        var selector: String
        var value: String
        var checked: Bool?
    }
    var url: String
    var x: Double
    var y: Double
    var fields: [Field]
}

extension BrowserPage {
    func checkpointNativeState() {
        guard let owner = sessionOwner, owner.pages[id] === self, let (s, t) = owner.tabIndex(id) else { return }
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
        guard let owner = sessionOwner, owner.pages[id] === self, owner.tabIndex(id) != nil,
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
}
