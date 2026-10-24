import WebKit

@MainActor
enum BrowserUserActivityBridge {
    static let messageHandlerName = "crestUserActivity"
    static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.user-activity"
    )

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor () -> Void
    ) -> BrowserUserActivityScriptMessageProxy {
        let proxy = BrowserUserActivityScriptMessageProxy(receive: receive)
        userContentController.add(
            proxy,
            contentWorld: contentWorld,
            name: messageHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
        return proxy
    }

    private static let source = #"""
        (() => {
          let lastSignal = -Infinity;
          let trailingSignal = 0;
          const deliver = () => {
            trailingSignal = 0;
            lastSignal = performance.now();
            try {
              globalThis.webkit.messageHandlers.crestUserActivity.postMessage(true);
            } catch (_) {}
          };
          const signal = event => {
            if (!event.isTrusted) return;
            const now = performance.now();
            const remaining = 15000 - (now - lastSignal);
            if (remaining <= 0) {
              if (trailingSignal) clearTimeout(trailingSignal);
              deliver();
              return;
            }
            if (trailingSignal) clearTimeout(trailingSignal);
            trailingSignal = setTimeout(deliver, remaining);
          };
          for (const type of ["pointerdown", "keydown", "wheel", "touchstart"]) {
            globalThis.addEventListener(type, signal, { capture: true, passive: true });
          }
        })();
        """#
}
