import Foundation
import WebKit

@MainActor
final class BrowserBlockedPopupScriptMessageProxy: NSObject, WKScriptMessageHandler {
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

/// Observes the result of top-level document calls to WebKit's native
/// `window.open` without deciding whether a window is allowed or creating one.
/// WebKit remains the sole popup policy engine and accepted requests continue to
/// `WKUIDelegate`, where `BrowserPopupCoordinator` preserves opener semantics.
@MainActor
enum BrowserBlockedPopupContentBridge {
    static let messageHandlerName = "crestBlockedPopup"
    static let contentWorld = WKContentWorld.page

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserBlockedPopupScriptMessageProxy {
        let proxy = BrowserBlockedPopupScriptMessageProxy(receive: receive)
        userContentController.add(
            proxy,
            contentWorld: contentWorld,
            name: messageHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: contentWorld
            )
        )
        return proxy
    }

    /// The smallest page-world seam capable of seeing WebKit's rejected result.
    /// A `Proxy` keeps the native callable as the invocation target while
    /// forwarding every argument, receiver, return value, exception, and
    /// allowed `WindowProxy` unchanged.
    static let source = #"""
        (() => {
          "use strict";
          const nativeOpen = globalThis.open;
          const descriptor = Object.getOwnPropertyDescriptor(globalThis, "open");
          const handler = globalThis.webkit?.messageHandlers?.crestBlockedPopup;
          if (typeof nativeOpen !== "function" || !descriptor || !("value" in descriptor) || !handler) {
            return;
          }

          const documentIdentifier = globalThis.crypto?.randomUUID?.()
            || `${Date.now()}-${Math.random()}`;
          let didReport = false;
          const observedOpen = new Proxy(nativeOpen, {
            apply(target, receiver, argumentsList) {
              const hadUserActivation = globalThis.navigator?.userActivation?.isActive === true;
              const result = Reflect.apply(target, receiver, argumentsList);
              if (result === null && !hadUserActivation && !didReport) {
                didReport = true;
                try {
                  handler.postMessage({
                    version: 1,
                    event: "blocked",
                    documentIdentifier,
                    userActivated: false
                  });
                } catch (_) {}
              }
              return result;
            }
          });

          try {
            Object.defineProperty(globalThis, "open", {
              ...descriptor,
              value: observedOpen
            });
          } catch (_) {}
        })();
        """#
}
