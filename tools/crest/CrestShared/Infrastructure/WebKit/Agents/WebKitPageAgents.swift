import Foundation
import WebKit

#if os(macOS)
    /// What an agent the person allowed does in WebKit's pages. Its scripts run
    /// in a content world of their own, which neither the page nor Crest's
    /// bridges see, or in the page's world when the person lets agents run
    /// scripts there. WebKit synthesizes no trusted input for a script, so
    /// input reaches the page as DOM events, which a page can tell apart from
    /// the person's own. Console messages and resource timings come from a
    /// small observer installed in the page's world only while an agent
    /// watches the page, which needs a page that owns its content controller.
    @MainActor
    final class WebKitPageAgents {
        // MARK: - Types

        /// What an agent watching one page kept of its activity.
        struct Activity {
            var console: [PageConsoleMessage] = []
            var network: [PageNetworkRequest] = []
            var consoleSequence: Int64 = 0
            var networkSequence: Int64 = 0
            var consoleDropped: Int64 = 0
            var networkDropped: Int64 = 0
        }

        // MARK: - Static Variables

        /// The world agents' scripts run in.
        static let agentWorld = WKContentWorld.world(name: "Crest.Agent")
        /// The most console messages and requests a page keeps.
        static let maximumKept = 500
        static let maximumText = 4096
        private static let handlerName = "crestAgentActivity"

        // MARK: - Variables

        private unowned let pages: WebKitEnginePages
        private let present: @MainActor (EnginePresentation) -> Void
        /// The activity each watched page kept, by page.
        private var activities: [UUID: Activity] = [:]
        /// The pages whose world has the activity observer, which stays for the
        /// page's life; its posts go nowhere once no handler listens.
        private var observed: Set<UUID> = []
        private var handlers: [UUID: WebKitAgentActivityHandler] = [:]

        // MARK: - Initializers

        init(pages: WebKitEnginePages, present: @escaping @MainActor (EnginePresentation) -> Void) {
            self.pages = pages
            self.present = present
        }

        // MARK: - Actions - Scripts

        func evaluate(_ request: EvaluatePageScript) -> Bool {
            guard let page = pages.page(request.pageID) else { return false }
            let world = request.world == .page ? WKContentWorld.page : Self.agentWorld
            Task { @MainActor [weak self] in
                let answer: PageScriptEvaluated
                do {
                    let value = try await page.webView.callAsyncJavaScript(
                        request.source, arguments: [:], in: nil, contentWorld: world)
                    answer = PageScriptEvaluated(
                        pageID: request.pageID, evaluationID: request.evaluationID, json: Self.json(value), error: nil)
                } catch {
                    answer = PageScriptEvaluated(
                        pageID: request.pageID, evaluationID: request.evaluationID, json: nil,
                        error: Self.message(of: error))
                }
                self?.present(.pageScriptEvaluated(answer))
            }
            return true
        }

        // MARK: - Actions - Input

        func click(_ request: ClickPage) -> Bool {
            synthesize(
                request.pageID, request.inputID,
                [
                    "kind": "click", "x": request.point.x, "y": request.point.y, "button": request.button.rawValue,
                    "count": request.count, "modifiers": request.modifiers.rawValue,
                ])
        }

        func hover(_ request: HoverPage) -> Bool {
            synthesize(request.pageID, request.inputID, ["kind": "hover", "x": request.point.x, "y": request.point.y])
        }

        func scroll(_ request: ScrollPage) -> Bool {
            synthesize(
                request.pageID, request.inputID,
                [
                    "kind": "scroll", "x": request.point.x, "y": request.point.y, "dx": request.deltaX,
                    "dy": request.deltaY,
                ])
        }

        func type(_ request: TypeInPage) -> Bool {
            synthesize(request.pageID, request.inputID, ["kind": "type", "text": request.text])
        }

        func press(_ request: PressKeyInPage) -> Bool {
            synthesize(
                request.pageID, request.inputID,
                [
                    "kind": "key", "key": request.key.key, "code": request.key.code, "keyCode": request.key.keyCode,
                    "text": request.key.text ?? "", "modifiers": request.modifiers.rawValue,
                ])
        }

        // MARK: - Actions - Activity

        func observe(_ request: ObservePageActivity) -> Bool {
            guard let page = pages.page(request.pageID) else { return false }
            guard request.observing else {
                activities[request.pageID] = nil
                if let handler = handlers.removeValue(forKey: request.pageID), page.ownsUserContentController {
                    page.webView.configuration.userContentController.removeScriptMessageHandler(
                        forName: Self.handlerName, contentWorld: .page)
                    handler.stop()
                }
                return true
            }
            // A popup shares its opener's controller, whose handlers it must
            // leave alone.
            guard page.ownsUserContentController else { return false }
            if activities[request.pageID] == nil { activities[request.pageID] = Activity() }
            if handlers[request.pageID] == nil {
                let handler = WebKitAgentActivityHandler(pageID: request.pageID, webView: page.webView) {
                    [weak self] pageID, message in
                    self?.keep(message, for: pageID)
                }
                handlers[request.pageID] = handler
                page.webView.configuration.userContentController.add(
                    handler, contentWorld: .page, name: Self.handlerName)
            }
            if !observed.contains(request.pageID) {
                observed.insert(request.pageID)
                page.webView.configuration.userContentController.addUserScript(
                    WKUserScript(
                        source: Self.observerSource, injectionTime: .atDocumentStart, forMainFrameOnly: true,
                        in: .page))
                page.webView.evaluateJavaScript(Self.observerSource, in: nil, in: .page) { _ in }
            }
            return true
        }

        func console(_ request: ReadPageConsole) -> PageConsoleLog {
            let activity = activities[request.pageID] ?? Activity()
            return PageConsoleLog(
                messages: activity.console.filter { $0.sequence > request.after }, dropped: activity.consoleDropped)
        }

        func network(_ request: ReadPageNetwork) -> PageNetworkLog {
            let activity = activities[request.pageID] ?? Activity()
            return PageNetworkLog(
                requests: activity.network.filter { $0.sequence > request.after }, dropped: activity.networkDropped)
        }

        // MARK: - Actions - Rendering

        /// WebKit keeps rendering a page no window shows; one that was never
        /// shown takes the size an agent asks for, so its layout and captures
        /// have one.
        func hold(_ request: HoldPageRendering) -> Bool {
            guard let page = pages.page(request.pageID) else { return false }
            guard request.held else { return true }
            guard request.width >= 1, request.height >= 1 else { return false }
            if page.webView.window == nil, page.webView.frame.isEmpty {
                page.webView.frame = CGRect(x: 0, y: 0, width: request.width, height: request.height)
            }
            return true
        }

        // MARK: - Mutators

        private func synthesize(_ pageID: UUID, _ inputID: UUID, _ input: [String: Any]) -> Bool {
            guard let page = pages.page(pageID) else { return false }
            Task { @MainActor [weak self] in
                let delivered =
                    (try? await page.webView.callAsyncJavaScript(
                        Self.inputSource, arguments: ["input": input], in: nil, contentWorld: Self.agentWorld))
                    as? Bool ?? false
                self?.present(
                    .pageInputDelivered(
                        PageInputDelivered(pageID: pageID, inputID: inputID, delivered: delivered, trusted: false)))
            }
            return true
        }

        private func keep(_ message: WebKitAgentActivityMessage, for pageID: UUID) {
            guard var activity = activities[pageID] else { return }
            message.kind.keep(message, in: &activity)
            activities[pageID] = activity
        }

        // MARK: - Actions - Values

        /// A script's value as JSON, or JSON null for one with no JSON form.
        private static func json(_ value: Any?) -> String {
            guard let value, !(value is NSNull),
                let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            else { return "null" }
            return String(decoding: data, as: UTF8.self)
        }

        /// What a script threw, as its message says.
        private static func message(of error: any Error) -> String {
            let info = (error as NSError).userInfo
            let message = info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            return String(message.prefix(maximumText))
        }

        // MARK: - Static Variables - Scripts

        /// Delivers one piece of input as the DOM events the person's own would
        /// cause, at a point in the viewport or to the focused element.
        private static let inputSource = #"""
            const modifiers = input.modifiers || 0;
            const keys = { shiftKey: !!(modifiers & 1), ctrlKey: !!(modifiers & 2), altKey: !!(modifiers & 4), metaKey: !!(modifiers & 8) };
            const pointer = (type, target, extra) => target.dispatchEvent(new (type.startsWith("pointer") ? PointerEvent : MouseEvent)(type, {
              bubbles: true, cancelable: true, composed: true, view: window, clientX: input.x, clientY: input.y, ...keys, ...extra }));
            const focusable = (element) => element.closest("input, textarea, select, button, a[href], [tabindex], [contenteditable=''], [contenteditable='true']");
            const editable = (element) => element && (element.isContentEditable || element.tagName === "TEXTAREA" ||
              (element.tagName === "INPUT" && !["button", "checkbox", "radio", "submit", "reset", "file", "image", "range", "color"].includes(element.type)));
            const insert = (element, text) => {
              if (element.isContentEditable) return document.execCommand("insertText", false, text);
              const prototype = element.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
              const setter = Object.getOwnPropertyDescriptor(prototype, "value").set;
              const start = element.selectionStart ?? element.value.length;
              const end = element.selectionEnd ?? element.value.length;
              if (!element.dispatchEvent(new InputEvent("beforeinput", { bubbles: true, cancelable: true, inputType: "insertText", data: text }))) return true;
              setter.call(element, element.value.slice(0, start) + text + element.value.slice(end));
              try { element.setSelectionRange(start + text.length, start + text.length); } catch {}
              element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
              return true;
            };
            switch (input.kind) {
            case "click": {
              const target = document.elementFromPoint(input.x, input.y);
              if (!target) return false;
              const button = input.button === 1 ? 2 : input.button === 2 ? 1 : 0;
              pointer("pointerover", target); pointer("mouseover", target); pointer("pointermove", target); pointer("mousemove", target);
              for (let click = 1; click <= input.count; click++) {
                pointer("pointerdown", target, { button, buttons: 1, detail: click });
                pointer("mousedown", target, { button, buttons: 1, detail: click });
                if (click === 1) focusable(target)?.focus?.();
                pointer("pointerup", target, { button, detail: click });
                pointer("mouseup", target, { button, detail: click });
                if (button === 0) pointer("click", target, { button, detail: click });
                else if (button === 2) pointer("contextmenu", target, { button, detail: click });
              }
              if (input.count === 2 && button === 0) pointer("dblclick", target, { button, detail: 2 });
              return true;
            }
            case "hover": {
              const target = document.elementFromPoint(input.x, input.y);
              if (!target) return false;
              pointer("pointerover", target); pointer("mouseover", target); pointer("pointermove", target); pointer("mousemove", target);
              return true;
            }
            case "scroll": {
              let target = document.elementFromPoint(input.x, input.y);
              while (target && target !== document.documentElement) {
                const style = getComputedStyle(target);
                if ((target.scrollHeight > target.clientHeight && /(auto|scroll)/.test(style.overflowY)) ||
                    (target.scrollWidth > target.clientWidth && /(auto|scroll)/.test(style.overflowX))) break;
                target = target.parentElement;
              }
              (target && target !== document.documentElement ? target : (document.scrollingElement || document.documentElement)).scrollBy(input.dx, input.dy);
              return true;
            }
            case "type": {
              const target = document.activeElement;
              return editable(target) ? insert(target, input.text) : false;
            }
            case "key": {
              const target = document.activeElement || document.body;
              const init = { key: input.key, code: input.code, keyCode: input.keyCode, which: input.keyCode, bubbles: true, cancelable: true, composed: true, ...keys };
              const proceeds = target.dispatchEvent(new KeyboardEvent("keydown", init));
              if (proceeds && input.text) target.dispatchEvent(new KeyboardEvent("keypress", init));
              if (proceeds) {
                if (input.key === "Enter" && target.form && target.tagName === "INPUT") target.form.requestSubmit();
                else if (input.key === "Enter" && target.matches?.("a[href], button")) target.click();
                else if (input.key === "Backspace" && editable(target) && !target.isContentEditable) {
                  const start = target.selectionStart ?? target.value.length;
                  const end = target.selectionEnd ?? target.value.length;
                  const from = start === end ? Math.max(0, start - 1) : start;
                  Object.getOwnPropertyDescriptor(target.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, "value").set
                    .call(target, target.value.slice(0, from) + target.value.slice(end));
                  target.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "deleteContentBackward" }));
                } else if (input.key === "Tab") {
                  const order = [...document.querySelectorAll("input, textarea, select, button, a[href], [tabindex]:not([tabindex='-1'])")]
                    .filter((element) => !element.disabled && element.getClientRects().length);
                  const next = order[(order.indexOf(target) + (keys.shiftKey ? order.length - 1 : 1)) % order.length];
                  next?.focus();
                } else if (input.text && editable(target)) insert(target, input.text);
              }
              target.dispatchEvent(new KeyboardEvent("keyup", init));
              return true;
            }
            }
            return false;
            """#

        /// Reports the page's console messages, uncaught errors and resource
        /// timings to the agent watching it.
        private static let observerSource = #"""
            (() => {
              if (globalThis.__crestAgentActivity) return;
              globalThis.__crestAgentActivity = true;
              const post = (message) => { try { webkit.messageHandlers.crestAgentActivity.postMessage(message); } catch {} };
              const text = (values) => values.map((value) => {
                if (typeof value === "string") return value;
                try { return JSON.stringify(value); } catch { return String(value); }
              }).join(" ").slice(0, 4096);
              for (const [method, level] of [["debug", "debug"], ["log", "log"], ["info", "info"], ["warn", "warning"], ["error", "error"]]) {
                const original = console[method];
                console[method] = function (...values) {
                  post({ kind: "console", level, text: text(values) });
                  return original.apply(this, values);
                };
              }
              addEventListener("error", (event) => post({ kind: "console", level: "error", text: String(event.message), source: event.filename || null, line: event.lineno || 0 }));
              addEventListener("unhandledrejection", (event) => post({ kind: "console", level: "error", text: "Uncaught (in promise) " + String(event.reason?.message ?? event.reason) }));
              const report = (entries) => {
                for (const entry of entries) {
                  post({ kind: "network", url: entry.name, type: entry.initiatorType, status: entry.responseStatus || 0,
                         duration: entry.duration, bytes: entry.transferSize || 0, start: performance.timeOrigin + entry.startTime });
                }
              };
              try { report(performance.getEntriesByType("navigation")); } catch {}
              try { new PerformanceObserver((list) => report(list.getEntries())).observe({ type: "resource", buffered: true }); } catch {}
            })();
            """#
    }
#endif
