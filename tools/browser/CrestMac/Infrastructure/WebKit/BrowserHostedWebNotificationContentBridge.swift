import Foundation
import WebKit

/// Supplies the foreground Notifications API that public embedded WebKit does
/// not host itself. The bridge runs only in the main frame and native code
/// validates the frame, origin, Space decision, and system authorization again
/// before acting on any message.
@MainActor
enum BrowserHostedWebNotificationContentBridge {
    static let messageHandlerName = "crestHostedNotifications"
    static let contentWorld = WKContentWorld.page

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserHostedWebNotificationScriptMessageProxy {
        let proxy = BrowserHostedWebNotificationScriptMessageProxy(receive: receive)
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

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestHostedNotificationBridge || !globalThis.isSecureContext) return;

          const handler = webkit.messageHandlers.crestHostedNotifications;
          const instances = new Map();
          const pendingPermissions = new Map();
          let nextIdentifier = 1;
          let permission = "default";

          const post = (body) => {
            try { handler.postMessage({ version: 1, ...body }); } catch (_) {}
          };

          const emit = (notification, type) => {
            if (!notification) return;
            notification.dispatchEvent(new Event(type));
          };

          class CrestHostedNotification extends EventTarget {
            static get permission() { return permission; }
            static get maxActions() { return 0; }

            static requestPermission(callback) {
              const requestID = `permission-${nextIdentifier++}`;
              const result = new Promise((resolve) => {
                pendingPermissions.set(requestID, { resolve, callback });
                post({ action: "requestPermission", requestID });
              });
              return result;
            }

            constructor(title, options = {}) {
              super();
              if (permission !== "granted") {
                throw new DOMException(
                  "Notification permission has not been granted for this origin.",
                  "NotAllowedError"
                );
              }
              this.title = String(title);
              this.body = options.body == null ? "" : String(options.body);
              this.tag = options.tag == null ? "" : String(options.tag);
              this.lang = options.lang == null ? "" : String(options.lang);
              this.dir = options.dir === "rtl" ? "rtl" : options.dir === "ltr" ? "ltr" : "auto";
              this.data = options.data;
              this.silent = options.silent === true;
              this.requireInteraction = false;
              this.renotify = false;
              this.vibrate = [];
              this.actions = [];
              this.badge = "";
              this.icon = options.icon == null ? "" : String(options.icon);
              this.image = options.image == null ? "" : String(options.image);
              this.timestamp = Number.isFinite(options.timestamp) ? options.timestamp : Date.now();
              this.onclick = null;
              this.onshow = null;
              this.onerror = null;
              this.onclose = null;
              this.__crestIdentifier = `notification-${nextIdentifier++}`;
              instances.set(this.__crestIdentifier, this);
              post({
                action: "create",
                identifier: this.__crestIdentifier,
                title: this.title,
                body: this.body,
                silent: this.silent
              });
            }

            close() {
              if (!instances.delete(this.__crestIdentifier)) return;
              post({ action: "close", identifier: this.__crestIdentifier });
              emit(this, "close");
            }
          }

          for (const type of ["click", "show", "error", "close"]) {
            Object.defineProperty(CrestHostedNotification.prototype, `on${type}`, {
              configurable: true,
              enumerable: true,
              get() { return this[`__crest_on${type}`] || null; },
              set(value) {
                const key = `__crest_on${type}`;
                if (this[key]) this.removeEventListener(type, this[key]);
                this[key] = typeof value === "function" ? value : null;
                if (this[key]) this.addEventListener(type, this[key]);
              }
            });
          }

          const bridge = Object.freeze({
            receive(message) {
              if (!message || typeof message !== "object") return;
              if (message.type === "permission") {
                permission = message.permission === "granted"
                  ? "granted"
                  : message.permission === "denied" ? "denied" : "default";
                const pending = pendingPermissions.get(message.requestID);
                if (pending) {
                  pendingPermissions.delete(message.requestID);
                  pending.resolve(permission);
                  if (typeof pending.callback === "function") pending.callback(permission);
                }
                return;
              }
              if (message.type !== "event") return;
              const notification = instances.get(message.identifier);
              if (!notification) return;
              if (message.event === "click") emit(notification, "click");
              if (message.event === "show") emit(notification, "show");
              if (message.event === "error") emit(notification, "error");
            }
          });

          Object.defineProperty(globalThis, "__crestHostedNotificationBridge", {
            value: bridge,
            configurable: false,
            enumerable: false,
            writable: false
          });
          Object.defineProperty(globalThis, "Notification", {
            value: CrestHostedNotification,
            configurable: false,
            enumerable: false,
            writable: false
          });
          post({ action: "queryPermission", requestID: "initial" });
        })();
        """#
}
