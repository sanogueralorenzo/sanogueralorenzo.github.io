import WebKit

@MainActor
final class BrowserDocumentActivity: NSObject, WKScriptMessageHandler {
    private struct Frame {
        let info: WKFrameInfo
        let hasEdits: Bool
    }

    private static let messageName = "browserDocumentActivity"
    private weak var webView: BrowserNativeWebView?
    private var frames: [String: Frame] = [:]
    private var polledEdits = true

    var hasUnsavedEdits: Bool { polledEdits || frames.values.contains(where: \.hasEdits) }
    var childFrames: [WKFrameInfo] { frames.values.map(\.info).filter { !$0.isMainFrame } }

    init(webView: BrowserNativeWebView) {
        self.webView = webView
        super.init()
        let controller = webView.configuration.userContentController
        controller.add(self, contentWorld: .defaultClient, name: Self.messageName)
        controller.addUserScript(
            WKUserScript(
                source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
    }

    func navigationStarted() {
        webView?.contextSelection = ""
        frames.removeAll()
        polledEdits = true
    }

    func recordPolledEdits(_ hasEdits: Bool) {
        polledEdits = hasEdits
    }

    func invalidate() {
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.messageName, contentWorld: .defaultClient)
        frames.removeAll()
        webView = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView, message.webView === webView, let body = message.body as? [String: Any],
            let id = body["document"] as? String
        else { return }
        if let selection = body["selection"] as? String {
            webView.contextSelection = String(selection.prefix(4096))
        } else if body["removed"] as? Bool == true {
            frames[id] = nil
        } else if let dirty = body["dirty"] as? Bool, frames.count < 128 || frames[id] != nil {
            frames[id] = Frame(info: message.frameInfo, hasEdits: dirty)
        }
    }

    private static let script = #"""
        (() => {
          const documentID = crypto.getRandomValues(new Uint32Array(4)).join(':');
          const edited = new WeakSet();
          const handler = webkit.messageHandlers.browserDocumentActivity;
          const post = activity => {
            try { handler.postMessage({document:documentID,...activity}); } catch {}
          };
          const hasEdits = () => [...document.querySelectorAll('input,textarea,select,[contenteditable=true]')].some(field => {
            if (field.isContentEditable) return edited.has(field);
            if (field.type === 'checkbox' || field.type === 'radio') return field.checked !== field.defaultChecked;
            if (field.tagName === 'SELECT') return [...field.options].some(option => option.selected !== option.defaultSelected);
            return field.value !== field.defaultValue;
          });
          globalThis.__browserHasFormEdits = hasEdits;
          const reportEdits = () => post({dirty:hasEdits()});
          for (const type of ['input','change','reset']) {
            addEventListener(type, event => {
              if (event.target?.isContentEditable) edited.add(event.target);
              queueMicrotask(reportEdits);
            }, true);
          }
          addEventListener('DOMContentLoaded', reportEdits, {once:true});
          addEventListener('pagehide', () => post({removed:true}), {once:true});
          addEventListener('contextmenu', event => {
            if (!event.isTrusted) return;
            const selection = event.target?.type === 'password' ? '' : String(getSelection() || '');
            post({selection});
          }, true);
        })();
        """#
}
