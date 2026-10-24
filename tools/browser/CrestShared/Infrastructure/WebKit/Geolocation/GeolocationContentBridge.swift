import Foundation
import WebKit

/// Supplies Crest's standards-shaped Geolocation API. WebKit's site decision
/// delegate does not establish the host app's Core Location authorization, so
/// Crest owns both layers and never reports a site grant that macOS or iOS
/// cannot honor.
@MainActor
enum BrowserGeolocationContentBridge {
    static let messageHandlerName = "crestGeolocation"
    static let contentWorld = WKContentWorld.page

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserGeolocationScriptMessageProxy {
        let proxy = BrowserGeolocationScriptMessageProxy(receive: receive)
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

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestGeolocationBridge || !globalThis.isSecureContext) return;

          const handler = webkit.messageHandlers.crestGeolocation;
          const documentIdentifier = crypto.randomUUID();
          const pending = new Map();
          const watches = new Map();
          let nextIdentifier = 1;
          let permissionState = "prompt";

          const post = (body) => {
            try { handler.postMessage({ version: 1, documentIdentifier, ...body }); } catch (_) {}
          };

          const documentAllowsGeolocation = () => {
            const policy = document.permissionsPolicy || document.featurePolicy;
            return !policy || typeof policy.allowsFeature !== "function"
              || policy.allowsFeature("geolocation");
          };

          const normalizedOptions = (options = {}) => ({
            enableHighAccuracy: options?.enableHighAccuracy === true,
            maximumAge: Number.isFinite(Number(options?.maximumAge))
              ? Math.max(Number(options.maximumAge), 0) : 0,
            timeout: Number.isFinite(Number(options?.timeout))
              ? Math.max(Number(options.timeout), 0) : null
          });

          const positionError = (code, message) => Object.freeze({
            code,
            message,
            PERMISSION_DENIED: 1,
            POSITION_UNAVAILABLE: 2,
            TIMEOUT: 3
          });

          const scheduleTimeout = (registration) => {
            if (registration.options.timeout == null) return;
            registration.timer = setTimeout(() => {
              registration.timer = null;
              if (registration.kind === "current") {
                pending.delete(registration.identifier);
                post({ action: "cancel", identifier: registration.identifier });
              }
              registration.error?.(positionError(3, "The location request timed out."));
            }, registration.options.timeout);
          };

          const makeRegistration = (kind, identifier, success, error, options) => {
            const registration = {
              kind,
              identifier,
              success,
              error: typeof error === "function" ? error : null,
              options: normalizedOptions(options),
              timer: null
            };
            scheduleTimeout(registration);
            return registration;
          };

          const failForDocumentPolicy = (error) => {
            queueMicrotask(() => error?.(positionError(
              1,
              "Geolocation is disabled by this document's Permissions Policy."
            )));
          };

          const geolocation = Object.freeze({
            getCurrentPosition(success, error, options) {
              if (typeof success !== "function") {
                throw new TypeError("The success callback must be a function.");
              }
              if (!documentAllowsGeolocation()) {
                failForDocumentPolicy(error);
                return;
              }
              const identifier = `current-${nextIdentifier++}`;
              const registration = makeRegistration(
                "current", identifier, success, error, options
              );
              pending.set(identifier, registration);
              post({ action: "getCurrentPosition", identifier, options: registration.options });
            },

            watchPosition(success, error, options) {
              if (typeof success !== "function") {
                throw new TypeError("The success callback must be a function.");
              }
              const watchID = nextIdentifier++;
              const identifier = `watch-${watchID}`;
              if (!documentAllowsGeolocation()) {
                failForDocumentPolicy(error);
                return watchID;
              }
              const registration = makeRegistration(
                "watch", identifier, success, error, options
              );
              watches.set(watchID, registration);
              post({ action: "watchPosition", identifier, options: registration.options });
              return watchID;
            },

            clearWatch(watchID) {
              const registration = watches.get(Number(watchID));
              if (!registration) return;
              watches.delete(Number(watchID));
              if (registration.timer) clearTimeout(registration.timer);
              post({ action: "cancel", identifier: registration.identifier });
            }
          });

          class CrestGeolocationPermissionStatus extends EventTarget {
            get state() { return permissionState; }
            get onchange() { return this.__crestOnChange || null; }
            set onchange(value) {
              if (this.__crestOnChange) {
                this.removeEventListener("change", this.__crestOnChange);
              }
              this.__crestOnChange = typeof value === "function" ? value : null;
              if (this.__crestOnChange) {
                this.addEventListener("change", this.__crestOnChange);
              }
            }
          }
          const permissionStatus = new CrestGeolocationPermissionStatus();

          const bridge = Object.freeze({
            receive(message) {
              if (!message || typeof message !== "object") return;
              if (message.documentIdentifier && message.documentIdentifier !== documentIdentifier) return;
              if (message.type === "permission") {
                const nextState = message.state === "granted"
                  ? "granted" : message.state === "denied" ? "denied" : "prompt";
                if (permissionState !== nextState) {
                  permissionState = nextState;
                  permissionStatus.dispatchEvent(new Event("change"));
                }
                return;
              }
              const current = pending.get(message.identifier);
              const watch = Array.from(watches.values()).find(
                (registration) => registration.identifier === message.identifier
              );
              const registration = current || watch;
              if (!registration) return;
              if (registration.timer) {
                clearTimeout(registration.timer);
                registration.timer = null;
              }
              if (message.type === "position") {
                if (current) pending.delete(message.identifier);
                registration.success(Object.freeze({
                  coords: Object.freeze(message.coords),
                  timestamp: message.timestamp
                }));
                if (watch) scheduleTimeout(registration);
                return;
              }
              if (message.type === "error") {
                if (current) pending.delete(message.identifier);
                if (message.code === 1 && watch) {
                  for (const [watchID, candidate] of watches) {
                    if (candidate === watch) watches.delete(watchID);
                  }
                }
                registration.error?.(positionError(message.code, message.message));
                if (watch && message.code !== 1) scheduleTimeout(registration);
              }
            }
          });

          let installed = false;
          try {
            Object.defineProperty(navigator, "geolocation", {
              value: geolocation,
              configurable: false,
              enumerable: true,
              writable: false
            });
            installed = true;
          } catch (_) {
            try {
              Object.defineProperty(Object.getPrototypeOf(navigator), "geolocation", {
                get: () => geolocation,
                configurable: true,
                enumerable: true
              });
              installed = true;
            } catch (_) {}
          }
          if (!installed) return;

          Object.defineProperty(globalThis, "__crestGeolocationBridge", {
            value: bridge,
            configurable: false,
            enumerable: false,
            writable: false
          });

          const permissions = navigator.permissions;
          if (permissions && typeof permissions.query === "function") {
            const nativeQuery = permissions.query.bind(permissions);
            try {
              Object.defineProperty(permissions, "query", {
                configurable: true,
                value(descriptor) {
                  return descriptor?.name === "geolocation"
                    ? Promise.resolve(permissionStatus)
                    : nativeQuery(descriptor);
                }
              });
            } catch (_) {}
          }

          addEventListener("pagehide", () => post({ action: "cancelAll" }), {
            once: true
          });
          post({ action: "queryPermission" });
        })();
        """#
}
