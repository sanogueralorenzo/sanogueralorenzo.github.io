import Foundation

/// The credential bridge every engine's pages run: its script and the name
/// its messages arrive under. How an engine installs it lives with the engine.
@MainActor
enum BrowserCredentialContentBridge {
    static let messageHandlerName = "crestCredentials"

    #if DEBUG
        private static let testingMethods = #"""
                ,
                inspectForTesting(selector) {
                  const selectedRoot = document.querySelector(selector);
                  const root = selectedRoot?.shadowRoot || selectedRoot;
                  if (!root) return null;
                  const selection = passwordSelection(root);
                  if (!selection) return null;
                  const usernameInput = usernameInputIn(root, selection.input);
                  return {
                    formID: idFor(root),
                    username: usernameInput?.value?.trim() || "",
                    passwordKind: selection.kind,
                    passwordFieldID: selection.input.id || selection.input.name || "",
                    passwordFieldCount: selection.count,
                    passwordLength: selection.input.value.length
                  };
                },
                captureForTesting(selector) {
                  const selectedRoot = document.querySelector(selector);
                  const root = selectedRoot?.shadowRoot || selectedRoot;
                  if (!root) return false;
                  captureFormInteraction(root, true);
                  return true;
                },
                focusForTesting(selector) {
                  const input = document.querySelector(selector);
                  if (!(input instanceof HTMLInputElement) || input.type !== "password") {
                    return false;
                  }
                  return reportFocus(input);
                }
            """#
    #else
        private static let testingMethods = ""
    #endif

    static let source = #"""
        (() => {
          "use strict";
          if (globalThis.__crestCredentialBridge) return;

          const handler = webkit.messageHandlers.crestCredentials;
          const rootsByID = new Map();
          const idsByRoot = new WeakMap();
          const observersByRoot = new WeakMap();
          let nextID = 1;
          let pendingSubmission = false;
          let trackedField = null;
          let trackedFieldRect = null;
          let lastSubmissionFingerprint = "";
          let lastSubmissionTime = 0;
          let lastUsernameFingerprint = "";
          let lastUsernameTime = 0;
          let observeRoot = () => {};

          const post = (body) => {
            try { handler.postMessage({ version: 1, ...body }); } catch (_) {}
          };

          const isVisible = (element) => {
            if (!(element instanceof HTMLInputElement) || element.disabled) return false;
            const style = getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
          };

          // Where the field sits in this frame's own viewport, in CSS pixels.
          // The host turns that into its own points; it is the only side that
          // knows the page's zoom, and the only side that knows whether this
          // frame is the one the prompt may be anchored inside.
          const rectOf = (element) => {
            const rect = element.getBoundingClientRect();
            if (!(rect.width > 0) || !(rect.height > 0)) return null;
            const values = [rect.left, rect.top, rect.width, rect.height];
            if (!values.every(Number.isFinite)) return null;
            return { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
          };

          const rectsDiffer = (left, right) => !left || !right
            || Math.abs(left.x - right.x) >= 0.5
            || Math.abs(left.y - right.y) >= 0.5
            || Math.abs(left.width - right.width) >= 0.5
            || Math.abs(left.height - right.height) >= 0.5;

          // WebKit already delivers scroll events at most once per rendering
          // update, so the change gate below is the whole of the throttling:
          // a page that scrolls without moving the field posts nothing.
          const reportFieldGeometry = () => {
            if (!trackedField) return;
            const input = trackedField.input.deref();
            if (!input || !input.isConnected || !isVisible(input)) {
              trackedField = null;
              trackedFieldRect = null;
              return;
            }
            const rect = rectOf(input);
            if (!rect || !rectsDiffer(rect, trackedFieldRect)) return;
            trackedFieldRect = rect;
            post({
              event: "fieldGeometry",
              trusted: false,
              formID: trackedField.formID,
              fieldRect: rect
            });
          };

          const rootFor = (element) => {
            if (element.form) return element.form;
            const semanticRoot = element.closest("form, [role='form']");
            if (semanticRoot) return semanticRoot;
            const treeRoot = element.getRootNode();
            return treeRoot instanceof ShadowRoot ? treeRoot : document.body;
          };

          const elementFromEvent = (event) => {
            const path = typeof event.composedPath === "function" ? event.composedPath() : [];
            return path.find((node) => node instanceof Element)
              || (event.target instanceof Element ? event.target : null);
          };

          const passwordInputFromEvent = (event) => {
            const path = typeof event.composedPath === "function" ? event.composedPath() : [];
            return path.find((node) => node instanceof HTMLInputElement && node.type === "password")
              || (event.target instanceof HTMLInputElement && event.target.type === "password"
                ? event.target
                : null);
          };

          const idFor = (root) => {
            let id = idsByRoot.get(root);
            if (!id) {
              id = `form-${nextID++}`;
              idsByRoot.set(root, id);
              rootsByID.set(id, new WeakRef(root));
              observeRoot(root);
            }
            return id;
          };

          const inputsIn = (root) => Array.from(root.querySelectorAll("input"));

          const passwordInputsIn = (root) => inputsIn(root).filter((input) =>
            input.type === "password" && isVisible(input)
          );

          const credentialScopeFor = (root, input) =>
            input?.closest("form, [role='form']") || root;

          const spansIndependentCredentialScopes = (root, inputs) =>
            new Set(inputs.map((input) => credentialScopeFor(root, input))).size > 1;

          const passwordKind = (input) =>
            input.autocomplete.toLowerCase().includes("new-password") ? "new" : "current";

          const passwordSelection = (root, preferredInput = null) => {
            const inputs = passwordInputsIn(root);
            if (!inputs.length) return null;
            if (spansIndependentCredentialScopes(root, inputs)) return null;
            if (preferredInput && inputs.includes(preferredInput)) {
              return { input: preferredInput, kind: passwordKind(preferredInput), count: inputs.length };
            }

            const explicitNewInputs = inputs.filter((input) => passwordKind(input) === "new");
            if (explicitNewInputs.length) {
              const populated = explicitNewInputs.filter((input) => input.value);
              if (new Set(populated.map((input) => input.value)).size > 1) return null;
              return {
                input: populated[0] || explicitNewInputs[0],
                kind: "new",
                count: inputs.length
              };
            }

            if (inputs.length >= 2) {
              const likelyNewInputs = inputs.slice(-2);
              if (inputs.length >= 3
                  && likelyNewInputs.every((input) => input.value)
                  && likelyNewInputs[0].value !== likelyNewInputs[1].value) {
                return null;
              }
              return { input: inputs[inputs.length - 1], kind: "new", count: inputs.length };
            }

            return { input: inputs[0], kind: "current", count: 1 };
          };

          const usernameInputIn = (root, passwordInput) => {
            const inputs = inputsIn(credentialScopeFor(root, passwordInput)).filter(isVisible);
            return inputs.find((input) => input.autocomplete.toLowerCase().includes("username"))
              || inputs.find((input) => input.type === "email")
              || inputs.slice(0, Math.max(inputs.indexOf(passwordInput), 0)).reverse().find((input) =>
                input.type === "text" || input.type === "email" || input.type === "tel"
              )
              || inputs.find((input) => input.type === "text" || input.type === "email");
          };

          const snapshot = (root, preferredPasswordInput = null) => {
            const selection = passwordSelection(root, preferredPasswordInput);
            if (!selection) return null;
            const passwordInput = selection.input;
            const usernameInput = usernameInputIn(root, passwordInput);
            return {
              formID: idFor(root),
              username: usernameInput?.value?.trim() || "",
              password: passwordInput.value || "",
              passwordKind: selection.kind
            };
          };

          const captureSubmission = (root, trusted) => {
            if (!trusted) return;
            const fields = snapshot(root);
            if (!fields || !fields.password) return;
            const now = Date.now();
            const fingerprint = `${fields.formID}\u0000${fields.username}`;
            if (fingerprint === lastSubmissionFingerprint && now - lastSubmissionTime < 750) return;
            lastSubmissionFingerprint = fingerprint;
            lastSubmissionTime = now;
            pendingSubmission = true;
            const body = {
              event: "submit",
              trusted: true,
              formID: fields.formID,
              password: fields.password,
              passwordKind: fields.passwordKind
            };
            if (fields.username) body.username = fields.username;
            post(body);
          };

          const captureUsernameStep = (root, trusted) => {
            if (!trusted || passwordInputsIn(root).length) return;
            const usernameInput = usernameInputIn(root, null);
            const username = usernameInput?.value?.trim() || "";
            if (!username) return;
            const formID = idFor(root);
            const now = Date.now();
            const fingerprint = `${formID}\u0000${username}`;
            if (fingerprint === lastUsernameFingerprint && now - lastUsernameTime < 750) return;
            lastUsernameFingerprint = fingerprint;
            lastUsernameTime = now;
            post({ event: "username", trusted: true, formID, username });
          };

          const captureFormInteraction = (root, trusted) => {
            if (passwordInputsIn(root).length) {
              captureSubmission(root, trusted);
            } else {
              captureUsernameStep(root, trusted);
            }
          };

          const hasVisiblePasswordField = () => {
            if (Array.from(document.querySelectorAll("input[type='password']")).some(isVisible)) {
              return true;
            }
            for (const [id, reference] of rootsByID) {
              const root = reference.deref();
              if (!root || !root.isConnected) {
                rootsByID.delete(id);
                continue;
              }
              if (root instanceof ShadowRoot
                  && Array.from(root.querySelectorAll("input[type='password']")).some(isVisible)) {
                return true;
              }
            }
            return false;
          };

          const reportDocumentState = () => post({
            event: "documentState",
            trusted: false,
            hasVisiblePasswordField: hasVisiblePasswordField()
          });

          const mutationOptions = {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ["hidden", "style", "class", "disabled", "type"]
          };

          const mutationDidOccur = () => {
            if (!pendingSubmission || hasVisiblePasswordField()) return;
            pendingSubmission = false;
            reportDocumentState();
          };

          observeRoot = (root) => {
            if (observersByRoot.has(root)) return;
            const observer = new MutationObserver(mutationDidOccur);
            observer.observe(root, mutationOptions);
            observersByRoot.set(root, observer);
          };

          // Raising the prompt, and starting to follow the field it points at.
          // The listener and the testing hook go through here together so the
          // hook cannot drift away from the path a real focus takes.
          const reportFocus = (input) => {
            const root = rootFor(input);
            const fields = snapshot(root, input);
            if (!fields) return false;
            const rect = rectOf(input);
            trackedField = rect ? { input: new WeakRef(input), formID: fields.formID } : null;
            trackedFieldRect = rect;
            post({
              event: "focus",
              trusted: true,
              formID: fields.formID,
              username: fields.username || undefined,
              passwordKind: fields.passwordKind,
              fieldRect: rect || undefined
            });
            return true;
          };

          const setInputValue = (input, value) => {
            const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
            if (setter) setter.call(input, value); else input.value = value;
            input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertReplacementText", data: null }));
            input.dispatchEvent(new Event("change", { bubbles: true }));
          };

          globalThis.__crestCredentialBridge = Object.freeze({
            fill(formID, username, password) {
              const root = rootsByID.get(formID)?.deref();
              if (!root || !root.isConnected) {
                rootsByID.delete(formID);
                return false;
              }
              const passwordInput = passwordInputsIn(root).find((input) => passwordKind(input) === "current");
              if (!passwordInput) return false;
              const usernameInput = usernameInputIn(root, passwordInput);
              if (usernameInput) setInputValue(usernameInput, username);
              setInputValue(passwordInput, password);
              passwordInput.focus();
              return true;
            },
            fillGenerated(formID, password) {
              const root = rootsByID.get(formID)?.deref();
              if (!root || !root.isConnected) {
                rootsByID.delete(formID);
                return false;
              }
              const inputs = passwordInputsIn(root);
              if (spansIndependentCredentialScopes(root, inputs)) return false;
              const newPasswordInputs = inputs.filter((input) => passwordKind(input) === "new");
              if (!newPasswordInputs.length) return false;
              newPasswordInputs.forEach((input) => setInputValue(input, password));
              newPasswordInputs[0].focus();
              return true;
            }
            \#(testingMethods)
          });

          document.addEventListener("focusin", (event) => {
            const input = passwordInputFromEvent(event);
            if (!event.isTrusted || !input) return;
            reportFocus(input);
          }, true);

          // The prompt is anchored under the focused field, so it stops
          // following once the page moves focus somewhere else. Focus leaving
          // the document altogether is the person reaching for the prompt
          // itself, which is exactly when it must keep following.
          document.addEventListener("focusout", (event) => {
            if (!trackedField || trackedField.input.deref() !== event.target) return;
            if (event.relatedTarget instanceof Element) {
              trackedField = null;
              trackedFieldRect = null;
            }
          }, true);

          addEventListener("scroll", reportFieldGeometry, { capture: true, passive: true });
          addEventListener("resize", reportFieldGeometry, { passive: true });

          document.addEventListener("submit", (event) => {
            captureFormInteraction(event.target, event.isTrusted);
          }, true);

          document.addEventListener("click", (event) => {
            if (!event.isTrusted) return;
            const target = elementFromEvent(event);
            if (!(target instanceof Element)) return;
            const control = target.closest("button, input[type='submit'], input[type='button']");
            if (!control) return;
            const root = rootFor(control);
            queueMicrotask(() => captureFormInteraction(root, true));
          }, true);

          document.addEventListener("keydown", (event) => {
            const input = elementFromEvent(event);
            if (!event.isTrusted
                || event.key !== "Enter"
                || !(input instanceof HTMLInputElement)) return;
            captureFormInteraction(rootFor(input), true);
          }, true);

          const begin = () => {
            observeRoot(document.documentElement);
            reportDocumentState();
          };

          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", begin, { once: true });
          } else {
            begin();
          }
        })();
        """#
}
