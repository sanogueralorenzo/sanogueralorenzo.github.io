import Foundation
import WebKit

/// Hears the media activity bridge of the pages WebKit's binding built.
@MainActor
final class WebKitMediaActivityMessageProxy: NSObject, WKScriptMessageHandler {
    private let receive: @MainActor (WKScriptMessage) -> Void

    init(receive: @escaping @MainActor (WKScriptMessage) -> Void) {
        self.receive = receive
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        receive(message)
    }
}

/// Tells WebKit's binding each time media in one of its pages, in any frame,
/// starts, stops or ends, so the page reports the media it runs to the core as
/// it changes. The message carries nothing: WebKit itself answers what the
/// page runs. It runs in a world of its own, which the page's scripts cannot
/// reach, and a popup that shares its opener's controller posts through the
/// opener's handler, which knows the popup by its web view.
@MainActor
enum WebKitMediaActivityBridge {
    // MARK: - Static Variables

    static let messageHandlerName = "crestMediaActivity"
    static let contentWorld = WKContentWorld.world(name: "CrestMediaActivity")

    /// Listens, in the capture phase, for the media events that start or end
    /// playback, and posts at most once per task however many arrive.
    static let source = #"""
        (() => {
          "use strict";
          const handler = globalThis.webkit?.messageHandlers?.crestMediaActivity;
          if (!handler) {
            return;
          }
          let posting = false;
          const post = () => {
            if (posting) {
              return;
            }
            posting = true;
            queueMicrotask(() => {
              posting = false;
              try {
                handler.postMessage(0);
              } catch (_) {}
            });
          };
          for (const type of ["play", "playing", "pause", "ended", "emptied", "abort"]) {
            document.addEventListener(type, post, { capture: true, passive: true });
          }
        })();
        """#

    // MARK: - Actions - Installing

    /// Installs the bridge in `userContentController`, whose messages
    /// `receive` hears.
    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> WebKitMediaActivityMessageProxy {
        let proxy = WebKitMediaActivityMessageProxy(receive: receive)
        userContentController.add(proxy, contentWorld: contentWorld, name: messageHandlerName)
        userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: contentWorld))
        return proxy
    }
}
