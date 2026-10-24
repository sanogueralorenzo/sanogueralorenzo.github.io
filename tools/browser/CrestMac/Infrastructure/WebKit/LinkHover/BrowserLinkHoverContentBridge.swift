import WebKit

@MainActor
enum BrowserLinkHoverContentBridge {
    static let name = "crestLinkHover"
    static let world = WKContentWorld.world(name: "com.pauldavis.crest.link-hover")

    static func install(in controller: WKUserContentController) {
        // A popup shares this controller. Route by the sending web view rather
        // than retaining the opener, so either page may close independently.
        controller.add(
            BrowserLinkContextScriptMessageProxy { message in
                (message.webView as? BrowserDesktopWebView)?.linkHover?.receive(message)
            },
            contentWorld: world,
            name: name
        )
        controller.addUserScript(
            WKUserScript(
                source: source, injectionTime: .atDocumentStart,
                forMainFrameOnly: false, in: world
            ))
    }

    static let validation = #"""
        return globalThis.__crestLinkHover?.validate(documentID, sequence, href) === true;
        """#

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestLinkHover) return;
          const documentID = `${Date.now()}-${Math.random()}`;
          let sequence = 0, link = null, href = null, point = null, scheduled = false;
          const options = { capture: true, passive: true };
          const destination = (element) => {
            if (!element?.isConnected) return null;
            const raw = typeof element.href === "string" ? element.href : element.getAttribute("href");
            if (raw === null) return null;
            try {
              const url = new URL(raw, element.baseURI);
              url.username = "";
              url.password = "";
              return url.href.length <= 8192 ? url.href : null;
            } catch (_) { return null; }
          };
          const anchor = (nodes) => nodes.find(node =>
            node instanceof Element && node.matches("a[href], area[href]")) ?? null;
          const atPoint = () => {
            if (!point) return null;
            let element = document.elementFromPoint(point.x, point.y);
            for (let depth = 0; element?.shadowRoot && depth < 16; depth++) {
              const inner = element.shadowRoot.elementFromPoint(point.x, point.y);
              if (!inner || inner === element) break;
              element = inner;
            }
            return element?.closest("a[href], area[href]") ?? null;
          };
          const post = () => {
            try {
              webkit.messageHandlers.crestLinkHover.postMessage({
                version: 1, document: documentID, sequence: ++sequence, href
              });
            } catch (_) {}
          };
          const observer = new MutationObserver(() => schedule());
          const update = (next) => {
            const value = destination(next);
            if (next === link && value === href) return;
            observer.disconnect();
            link = value ? next : null;
            href = value;
            post();
            if (link) {
              const config = { subtree: true, childList: true, attributes: true,
                attributeFilter: ["href", "style", "class", "hidden"] };
              observer.observe(document, config);
              const root = link.getRootNode();
              if (root !== document) observer.observe(root, config);
            }
          };
          const schedule = () => {
            if (scheduled) return;
            scheduled = true;
            requestAnimationFrame(() => {
              scheduled = false;
              update(atPoint());
            });
          };
          const clear = () => { point = null; update(null); };
          globalThis.__crestLinkHover = {
            retire: (expectedDocument, expectedSequence) => {
              if (expectedDocument !== documentID || expectedSequence !== sequence) return;
              observer.disconnect();
              point = null;
              link = null;
              href = null;
              sequence++;
            },
            validate: (expectedDocument, expectedSequence, expectedHref) =>
              expectedDocument === documentID && expectedSequence === sequence
              && expectedHref === href && !!link?.isConnected
              && link.matches(":hover") && destination(link) === href
              && (link.localName === "area" || atPoint() === link)
          };
          addEventListener("pointerover", event => {
            if (!event.isTrusted || event.pointerType !== "mouse" || event.buttons) return;
            point = { x: event.clientX, y: event.clientY };
            const next = anchor(event.composedPath());
            if (next !== link) update(next);
          }, options);
          addEventListener("pointermove", event => {
            if (!event.isTrusted || event.pointerType !== "mouse" || event.buttons) return;
            point = { x: event.clientX, y: event.clientY };
            // Reading the composed path is cheap; DOM hit tests happen only
            // after a layout change or before publishing a delayed preview.
            const next = anchor(event.composedPath());
            if (next !== link) update(next);
          }, options);
          addEventListener("pointerout", event => {
            if (!event.isTrusted || event.pointerType !== "mouse") return;
            const next = event.relatedTarget instanceof Element
              ? event.relatedTarget.closest("a[href], area[href]") : null;
            if (next !== link) update(null);
            if (!event.relatedTarget) point = null;
          }, options);
          addEventListener("scroll", () => { update(null); schedule(); }, options);
          for (const name of ["pointerdown", "pointercancel", "dragstart", "keydown", "pagehide", "blur"]) {
            addEventListener(name, clear, options);
          }
          addEventListener("visibilitychange", () => { if (document.hidden) clear(); }, options);
          addEventListener("resize", () => { update(null); schedule(); }, options);
        })();
        """#
}
