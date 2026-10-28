import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Captures link geometry without cancelling native touches, menus, or navigation.
@MainActor
enum MobileLinkActivationContentBridge {
    static let messageHandlerName = "crestLinkActivation"
    static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.link-activation"
    )

    static func install(
        in userContentController: WKUserContentController
    ) -> MobileLinkActivationScriptMessageProxy {
        let proxy = MobileLinkActivationScriptMessageProxy()
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
          if (globalThis.__crestLinkActivationInstalled) return;
          globalThis.__crestLinkActivationInstalled = true;

          globalThis.addEventListener('pointerdown', event => {
            if (!event.isTrusted || (event.button !== undefined && event.button !== 0)) return;
            const target = event.target instanceof Element ? event.target : null;
            const link = event.composedPath().find(
              node => node instanceof Element && node.matches?.('a[href], area[href]')
            ) || target?.closest?.('a[href], area[href]');
            if (!link) return;

            let destination;
            try {
              destination = new URL(link.href, document.baseURI);
            } catch (_) {
              return;
            }
            if (destination.protocol !== 'http:' && destination.protocol !== 'https:') return;

            const rect = link.getBoundingClientRect();
            const viewportWidth = Math.max(globalThis.innerWidth, 1);
            const viewportHeight = Math.max(globalThis.innerHeight, 1);
            const label = (
              link.innerText ||
              link.getAttribute('aria-label') ||
              link.getAttribute('title') ||
              destination.hostname
            ).trim();
            try {
              globalThis.webkit.messageHandlers.crestLinkActivation.postMessage({
                href: destination.href,
                label,
                minX: rect.left / viewportWidth,
                minY: rect.top / viewportHeight,
                width: rect.width / viewportWidth,
                height: rect.height / viewportHeight,
                touchX: event.clientX / viewportWidth,
                touchY: event.clientY / viewportHeight
              });
            } catch (_) {}
          }, { capture: true, passive: true });
        })();
        """#
}
