import WebKit

@MainActor
enum BrowserLinkDragContentBridge {
    static let name = "crestLinkDrag"
    static let world = WKContentWorld.world(name: "com.pauldavis.crest.link-drag")

    static func install(in controller: WKUserContentController) {
        controller.add(
            BrowserLinkContextScriptMessageProxy { message in
                (message.webView as? BrowserDesktopWebView)?.linkDrag?.receive(message)
            },
            contentWorld: world, name: name
        )
        controller.addUserScript(
            WKUserScript(
                source: source, injectionTime: .atDocumentStart,
                forMainFrameOnly: false, in: world
            ))
    }

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestLinkDrag) return;
          const documentID = `${Date.now()}-${Math.random()}`;
          let enabled = null, down = null, active = false, suppressClick = false;
          const post = (phase, fields = {}) => {
            try { webkit.messageHandlers.crestLinkDrag.postMessage({
              version: 1, document: documentID, phase, ...fields
            }); } catch (_) {}
          };
          const destination = link => {
            try {
              const url = new URL(link.href, link.baseURI);
              if (!['https:', 'http:'].includes(url.protocol) || url.href.length > 8192) return null;
              return url.href;
            } catch (_) { return null; }
          };
          globalThis.__crestLinkDrag = {
            configure: (value, available) => { enabled = available ? value === true : null; }
          };
          addEventListener('mousedown', event => {
            if (!event.isTrusted || event.button !== 0) return;
            down = null; active = false; suppressClick = false;
            if (enabled === null || event.metaKey || event.ctrlKey) return;
            const path = event.composedPath();
            // Linked images retain WebKit's image drag, as do selections and editors.
            if (path.some(node => node instanceof Element &&
                (node.matches('img, picture, svg, canvas, video, audio, input, textarea, select') ||
                 node.isContentEditable))) return;
            if (!getSelection()?.isCollapsed) return;
            const link = path.find(node => node instanceof Element && node.matches('a[href], area[href]'));
            if (!link || link.hasAttribute('download')) return;
            const href = destination(link);
            if (!href || (enabled === event.altKey)) return;
            down = { link, href, x: event.clientX, y: event.clientY };
          }, { capture: true, passive: true });
          addEventListener('dragstart', event => {
            if (!event.isTrusted || !down) return;
            if (!down.link.isConnected || destination(down.link) !== down.href ||
                event.target instanceof HTMLImageElement || !getSelection()?.isCollapsed) return;
            // Cancel only the chosen link's native URL drag, before AppKit starts it.
            event.preventDefault();
            if (active) return;
            active = true; suppressClick = true;
            post('begin', { href: down.href, label: (down.link.textContent || '').trim().slice(0, 160),
              deltaX: event.clientX - down.x, deltaY: event.clientY - down.y });
          }, { capture: true, passive: false });
          addEventListener('click', event => {
            if (!event.isTrusted || !suppressClick) return;
            event.preventDefault();
            event.stopImmediatePropagation();
          }, { capture: true, passive: false });
          addEventListener('pagehide', () => { post('retire'); down = null; active = false; },
            { capture: true, passive: true });
          addEventListener('pageshow', () => post('ready'), { capture: true, passive: true });
          post('ready');
        })();
        """#
}
