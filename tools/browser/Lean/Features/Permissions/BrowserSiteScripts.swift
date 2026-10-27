import Foundation

enum BrowserSiteScripts {
    static let geolocation = #"""
        (() => {
          "use strict";
          if (globalThis.__leanGeolocationBridge || !globalThis.isSecureContext) return;

          const handler = webkit.messageHandlers.leanGeolocation;
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

          class LeanGeolocationPermissionStatus extends EventTarget {
            get state() { return permissionState; }
            get onchange() { return this.__leanOnChange || null; }
            set onchange(value) {
              if (this.__leanOnChange) {
                this.removeEventListener("change", this.__leanOnChange);
              }
              this.__leanOnChange = typeof value === "function" ? value : null;
              if (this.__leanOnChange) {
                this.addEventListener("change", this.__leanOnChange);
              }
            }
          }
          const permissionStatus = new LeanGeolocationPermissionStatus();

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

          Object.defineProperty(globalThis, "__leanGeolocationBridge", {
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
    static let notifications = #"""
        (() => {
          "use strict";
          if (globalThis.__leanHostedNotificationBridge || !globalThis.isSecureContext) return;

          const handler = webkit.messageHandlers.leanHostedNotifications;
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

          class LeanHostedNotification extends EventTarget {
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
              this.__leanIdentifier = `notification-${nextIdentifier++}`;
              instances.set(this.__leanIdentifier, this);
              post({
                action: "create",
                identifier: this.__leanIdentifier,
                title: this.title,
                body: this.body,
                silent: this.silent
              });
            }

            close() {
              if (!instances.delete(this.__leanIdentifier)) return;
              post({ action: "close", identifier: this.__leanIdentifier });
              emit(this, "close");
            }
          }

          for (const type of ["click", "show", "error", "close"]) {
            Object.defineProperty(LeanHostedNotification.prototype, `on${type}`, {
              configurable: true,
              enumerable: true,
              get() { return this[`__lean_on${type}`] || null; },
              set(value) {
                const key = `__lean_on${type}`;
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

          Object.defineProperty(globalThis, "__leanHostedNotificationBridge", {
            value: bridge,
            configurable: false,
            enumerable: false,
            writable: false
          });
          Object.defineProperty(globalThis, "Notification", {
            value: LeanHostedNotification,
            configurable: false,
            enumerable: false,
            writable: false
          });
          post({ action: "queryPermission", requestID: "initial" });
        })();
        """#
}
