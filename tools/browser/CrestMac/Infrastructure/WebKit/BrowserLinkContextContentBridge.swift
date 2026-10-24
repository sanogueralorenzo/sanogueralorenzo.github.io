import Foundation
import WebKit

/// Reports the link and image under the cursor to the app before WebKit builds its
/// web-content context menu.
///
/// macOS has no `contextMenuConfigurationForElement` — that delegate callback
/// is iOS only — and resolving the element from `rightMouseDown` races WebKit's
/// own hit test. The `contextmenu` DOM event does not race it: the web content
/// process dispatches the event first and only then answers the UI process with
/// the menu, and messages from one process arrive in the order it sent them.
///
/// The listener runs in the capture phase, before page script can cancel
/// propagation, and posts on *every* right-click — including one that found no
/// link, which is what keeps the previous capture from surviving into a menu
/// opened over plain content.
@MainActor
enum BrowserLinkContextContentBridge {
    static let messageHandlerName = "crestLinkContext"
    static let contentWorld = WKContentWorld.world(
        name: "com.pauldavis.crest.link-context"
    )

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserLinkContextScriptMessageProxy {
        let proxy = BrowserLinkContextScriptMessageProxy(receive: receive)
        userContentController.add(
            proxy,
            contentWorld: contentWorld,
            name: messageHandlerName
        )
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                // A link inside an iframe opens the same menu as one in the
                // main frame, so every frame reports for itself.
                forMainFrameOnly: false,
                in: contentWorld
            )
        )
        return proxy
    }

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestLinkContextBridgeInstalled) return;
          globalThis.__crestLinkContextBridgeInstalled = true;

          let sequence = 0;

          const selectionText = (event) => {
            const element = event.target instanceof Element
              ? event.target
              : null;
            if (
              element instanceof HTMLInputElement
              || element instanceof HTMLTextAreaElement
            ) {
              const start = element.selectionStart;
              const end = element.selectionEnd;
              if (Number.isInteger(start) && Number.isInteger(end) && end > start) {
                return element.value.slice(start, end);
              }
            }
            const selected = globalThis.getSelection?.()?.toString() ?? "";
            return selected.length <= 4096 && selected.length > 0
              ? selected
              : null;
          };

          const isEditable = (event) => {
            const path = typeof event.composedPath === "function"
              ? event.composedPath()
              : [];
            return path.some((node) =>
              node instanceof HTMLElement
              && (
                node.isContentEditable
                || node instanceof HTMLTextAreaElement
                || (
                  node instanceof HTMLInputElement
                  && !["button", "checkbox", "color", "file", "hidden",
                    "image", "radio", "range", "reset", "submit"]
                    .includes(node.type)
                )
              )
            );
          };

          const post = (event, href, media) => {
            try {
              webkit.messageHandlers.crestLinkContext.postMessage({
                version: 3,
                token: ++sequence,
                href,
                imageURL: media?.type === "image" ? media.sourceURL : null,
                sourceURL: media?.sourceURL ?? null,
                mediaType: media?.type ?? null,
                selectionText: selectionText(event),
                editable: isEditable(event)
              });
            } catch (_) {}
          };

          const postActivation = (event, link, href) => {
            const rect = link.getBoundingClientRect();
            const viewportWidth = Math.max(globalThis.innerWidth, 1);
            const viewportHeight = Math.max(globalThis.innerHeight, 1);
            try {
              webkit.messageHandlers.crestLinkContext.postMessage({
                version: 1,
                kind: "activation",
                href,
                minX: rect.left / viewportWidth,
                minY: rect.top / viewportHeight,
                width: rect.width / viewportWidth,
                height: rect.height / viewportHeight,
                touchX: event.clientX / viewportWidth,
                touchY: event.clientY / viewportHeight
              });
            } catch (_) {}
          };

          const elementFromEvent = (event, selector) => {
            const path = typeof event.composedPath === "function"
              ? event.composedPath()
              : [];
            const composedElement = path.find((node) =>
              node instanceof Element && node.matches?.(selector)
            );
            if (composedElement) return composedElement;
            return event.target instanceof Element
              ? event.target.closest(selector)
              : null;
          };

          const linkFromEvent = (event) => {
            return elementFromEvent(event, "a[href], area[href]");
          };

          const destination = (event) => {
            const link = linkFromEvent(event);
            if (!link) return null;
            // An SVG anchor answers `href` with an SVGAnimatedString rather
            // than a resolved URL string, so fall back to the attribute and
            // let the element's own base document resolve it.
            const raw = typeof link.href === "string"
              ? link.href
              : link.getAttribute("href");
            if (!raw) return null;
            let resolved;
            try {
              resolved = new URL(raw, link.baseURI || document.baseURI);
            } catch (_) {
              return null;
            }
            if (resolved.protocol !== "http:" && resolved.protocol !== "https:") {
              return null;
            }
            return resolved.href;
          };

          const mediaDestination = (event) => {
            const media = elementFromEvent(
              event,
              "audio, img, input[type='image'], svg image, video"
            );
            if (!media) return null;
            const localName = media.localName?.toLowerCase();
            const type = localName === "audio"
              ? "audio"
              : localName === "video"
                ? "video"
                : "image";
            const raw = media.currentSrc
              || (typeof media.src === "string" ? media.src : null)
              || media.href?.baseVal
              || media.getAttribute("href")
              || media.getAttribute("src");
            if (!raw) return { type, sourceURL: null };
            let resolved;
            try {
              resolved = new URL(raw, media.baseURI || document.baseURI);
            } catch (_) {
              return { type, sourceURL: null };
            }
            if (!["http:", "https:", "blob:", "data:"].includes(resolved.protocol)) {
              return { type, sourceURL: null };
            }
            return {
              type,
              sourceURL: resolved.href.length <= 4096 ? resolved.href : null
            };
          };

          globalThis.addEventListener("pointerdown", (event) => {
            if (!event.isTrusted || (event.button !== undefined && event.button !== 0)) {
              return;
            }
            const link = linkFromEvent(event);
            const href = destination(event);
            if (!link || !href) return;
            postActivation(event, link, href);
          }, { capture: true, passive: true });

          globalThis.addEventListener("contextmenu", (event) => {
            if (!event.isTrusted) return;
            post(event, destination(event), mediaDestination(event));
          }, { capture: true, passive: true });
        })();
        """#
}
