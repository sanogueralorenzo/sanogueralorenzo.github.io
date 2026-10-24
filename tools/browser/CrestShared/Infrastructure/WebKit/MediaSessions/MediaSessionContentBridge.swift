import Foundation
import WebKit

@MainActor
final class BrowserMediaSessionScriptMessageProxy: NSObject,
    WKScriptMessageHandler
{
    private let receive: @MainActor (WKScriptMessage) -> Void

    init(receive: @escaping @MainActor (WKScriptMessage) -> Void) {
        self.receive = receive
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        receive(message)
    }
}

@MainActor
enum BrowserMediaSessionContentBridge {
    static let messageHandlerName = "crestMediaSession"
    static let contentWorld = WKContentWorld.page

    static func install(
        in userContentController: WKUserContentController,
        receive: @escaping @MainActor (WKScriptMessage) -> Void
    ) -> BrowserMediaSessionScriptMessageProxy {
        let proxy = BrowserMediaSessionScriptMessageProxy(receive: receive)
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
          if (globalThis.__crestMediaSessionBridge) return;
          const session = globalThis.navigator?.mediaSession;
          const messageHandler = globalThis.webkit?.messageHandlers?.crestMediaSession;
          if (!session || !messageHandler) return;

          let documentIdentifier = globalThis.crypto?.randomUUID?.()
            || `${Date.now()}-${Math.random()}`;
          const actionHandlers = new Map();
          const knownElements = new Set();
          let sequence = 0;
          let didObservePlayback = false;
          const qualifiedElements = new Map();
          const interacted = new WeakSet();
          const observedElements = new WeakSet();
          const observedRoots = new WeakSet();
          let pageActive = true;
          let scheduled = false;
          let explicitPlaybackQualified = false;
          \#(BrowserMediaPlayerPolicyScript.source)
          let artworkGeneration = 0;
          let artworkSource = null;
          let artworkDataURL = null;
          let artworkAbortController = null;

          const cleanText = value => {
            if (typeof value !== "string") return null;
            const trimmed = value.trim();
            return trimmed && trimmed.length <= 512 ? trimmed : null;
          };

          const selectedArtworkSource = () => {
            const artwork = session.metadata?.artwork;
            if (!Array.isArray(artwork)) return null;
            let selected = null;
            let selectedArea = -1;
            for (const item of artwork) {
              const source = item?.src;
              if (typeof source === "string" && source.length <=
                  \#(BrowserMediaSessionPageEventDecoder.maximumArtworkSourceCharacters)) {
                const match = /^(\d+)x(\d+)$/i.exec(item?.sizes || "");
                const area = match ? Number(match[1]) * Number(match[2]) : 0;
                if (!selected || area > selectedArea) {
                  selected = source;
                  selectedArea = area;
                }
              }
            }
            return selected;
          };

          const encodedArtworkBlob = (canvas, type, quality) =>
            new Promise(resolve => canvas.toBlob(resolve, type, quality));

          const artworkDataURLFromBlob = blob => new Promise(resolve => {
            const fileReader = new FileReader();
            fileReader.onerror = () => resolve(null);
            fileReader.onload = () => resolve(fileReader.result);
            fileReader.readAsDataURL(blob);
          });

          const boundedOversizeArtwork = async (sourceBlob, generation) => {
            let bitmap;
            try {
              bitmap = await createImageBitmap(sourceBlob);
            } catch (_) {
              return null;
            }
            if (generation !== artworkGeneration) {
              bitmap.close?.();
              return null;
            }
            const scale = Math.min(
              1,
              \#(BrowserMediaSessionPageEventDecoder.maximumOversizeArtworkPixelSize)
                / Math.max(bitmap.width, bitmap.height)
            );
            const canvas = document.createElement("canvas");
            canvas.width = Math.max(1, Math.round(bitmap.width * scale));
            canvas.height = Math.max(1, Math.round(bitmap.height * scale));
            const context = canvas.getContext("2d", { alpha: true });
            if (!context) {
              bitmap.close?.();
              return null;
            }
            context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
            bitmap.close?.();
            let encoded = await encodedArtworkBlob(
              canvas,
              sourceBlob.type === "image/jpeg" ? "image/jpeg" : "image/png",
              0.92
            );
            if (encoded?.size > \#(BrowserMediaSessionPageEventDecoder.maximumArtworkBytes)) {
              encoded = await encodedArtworkBlob(canvas, "image/jpeg", 0.86);
            }
            return encoded?.size <= \#(BrowserMediaSessionPageEventDecoder.maximumArtworkBytes)
              ? encoded : null;
          };

          const readBoundedArtwork = async (response, generation) => {
            const type = response.headers.get("content-type")?.split(";", 1)[0]?.toLowerCase();
            if (!["image/png", "image/jpeg", "image/webp"].includes(type)) return;
            const declaredLength = Number(response.headers.get("content-length"));
            if (Number.isFinite(declaredLength)
                && declaredLength > \#(BrowserMediaSessionPageEventDecoder.maximumArtworkInputBytes)) return;
            const reader = response.body?.getReader();
            if (!reader) return;
            const chunks = [];
            let total = 0;
            while (true) {
              const part = await reader.read();
              if (part.done) break;
              total += part.value.byteLength;
              if (total > \#(BrowserMediaSessionPageEventDecoder.maximumArtworkInputBytes)) {
                await reader.cancel();
                return;
              }
              chunks.push(part.value);
            }
            if (generation !== artworkGeneration) return;
            const sourceBlob = new Blob(chunks, { type });
            // Ordinary artwork crosses the bridge byte-for-byte. Rasterize only
            // when the original cannot fit the bounded native payload.
            const retainedBlob = sourceBlob.size
              <= \#(BrowserMediaSessionPageEventDecoder.maximumArtworkBytes)
              ? sourceBlob
              : await boundedOversizeArtwork(sourceBlob, generation);
            if (!retainedBlob || generation !== artworkGeneration) return;
            const dataURL = await artworkDataURLFromBlob(retainedBlob);
            if (generation !== artworkGeneration
                || typeof dataURL !== "string"
                || dataURL.length >
                    \#(BrowserMediaSessionPageEventDecoder.maximumArtworkDataURLCharacters)
                || !/^data:image\/(?:png|jpeg|webp);base64,/i.test(dataURL)) return;
            artworkDataURL = dataURL;
            post({});
          };

          const refreshArtwork = () => {
            const source = selectedArtworkSource();
            if (source === artworkSource) return;
            artworkSource = source;
            artworkDataURL = null;
            artworkGeneration += 1;
            artworkAbortController?.abort();
            artworkAbortController = null;
            if (!source) return;
            if (/^data:image\/(?:png|jpeg|webp);base64,/i.test(source)
                && source.length <=
                    \#(BrowserMediaSessionPageEventDecoder.maximumArtworkDataURLCharacters)) {
              artworkDataURL = source;
              return;
            }
            let url;
            try { url = new URL(source, globalThis.location.href); } catch (_) { return; }
            if (!["http:", "https:", "blob:", "data:"].includes(url.protocol)) return;
            const generation = artworkGeneration;
            artworkAbortController = new AbortController();
            fetch(url, {
              credentials: "same-origin",
              mode: "cors",
              signal: artworkAbortController.signal
            }).then(response => {
              if (!response.ok || generation !== artworkGeneration) return;
              return readBoundedArtwork(response, generation);
            }).catch(() => {});
          };

          const hasTransportHandlers = () => actionHandlers.has("play") && actionHandlers.has("pause");
          const hasExplicitAudioSession = () => hasTransportHandlers() && !!cleanText(session.metadata?.title);
          const mediaSource = element => element.currentSrc || element.src || "";
          const eligiblePlayer = element => {
            if (!element.isConnected || element.ended) return false;
            if (element instanceof HTMLVideoElement) {
              return element.readyState >= 2 && element.videoWidth > 0 && element.videoHeight > 0
                && !isDecorative(element) && hasPlayerControls(element, interacted.has(element));
            }
            return (!isDecorative(element) && hasPlayerControls(element, interacted.has(element)))
              || hasExplicitAudioSession();
          };
          const currentPlayers = () => {
            for (const element of knownElements) {
              if (!element.isConnected) {
                knownElements.delete(element);
                qualifiedElements.delete(element);
                continue;
              }
              const source = mediaSource(element);
              const prior = qualifiedElements.get(element);
              if (prior && (prior.source !== source || prior.stream !== element.srcObject)) {
                qualifiedElements.delete(element);
              }
              if (!eligiblePlayer(element)) {
                qualifiedElements.delete(element);
                continue;
              }
              // Video control eligibility is the same as PiP. Muted intentional
              // video remains valid; audio still needs audible playback to start.
              if (!element.paused && (element instanceof HTMLVideoElement || (!element.muted && element.volume > 0))) {
                qualifiedElements.set(element, { source, stream: element.srcObject });
              }
            }
            return Array.from(qualifiedElements.keys());
          };
          const hasExplicitNonElementPlayback = () => {
            if (didObservePlayback || knownElements.size > 0 || !hasExplicitAudioSession()) {
              explicitPlaybackQualified = false;
              return false;
            }
            if (session.playbackState === "playing") explicitPlaybackQualified = true;
            if (session.playbackState === "none") explicitPlaybackQualified = false;
            return explicitPlaybackQualified;
          };
          const isAudible = players => players.some(element =>
            !element.paused && !element.ended && !element.muted && element.volume > 0);

          const post = extra => {
            const metadata = session.metadata;
            const players = currentPlayers();
            const explicit = hasExplicitNonElementPlayback();
            const active = pageActive && (players.length > 0 || explicit);
            const playbackState = players.length
              ? (players.some(element => !element.paused) ? "playing" : "paused")
              : (explicit ? session.playbackState : "none");
            const actions = new Set(actionHandlers.keys());
            if (players.length) { actions.add("play"); actions.add("pause"); }
            try {
              messageHandler.postMessage({
                version: 1,
                documentIdentifier,
                sequence: ++sequence,
                location: String(globalThis.location.href).slice(0, 4096),
                invalidated: false,
                active,
                title: cleanText(metadata?.title),
                artist: cleanText(metadata?.artist),
                album: cleanText(metadata?.album),
                artworkDataURL,
                playbackState,
                audible: isAudible(players),
                muted: players.length > 0 && players.every(element => element.muted),
                actions: Array.from(actions),
                ...extra
              });
            } catch (_) {}
          };

          const wrapProperty = property => {
            let owner = session;
            let descriptor;
            while (owner && !descriptor) {
              descriptor = Object.getOwnPropertyDescriptor(owner, property);
              owner = Object.getPrototypeOf(owner);
            }
            if (!descriptor?.get || !descriptor?.set) return;
            try {
              Object.defineProperty(session, property, {
                configurable: true,
                enumerable: descriptor.enumerable,
                get() { return descriptor.get.call(session); },
                set(value) {
                  descriptor.set.call(session, value);
                  queueMicrotask(() => {
                    if (property === "metadata") refreshArtwork();
                    post({});
                  });
                }
              });
            } catch (_) {}
          };

          const nativeSetActionHandler = session.setActionHandler;
          if (typeof nativeSetActionHandler === "function") {
            const observedSetActionHandler = new Proxy(nativeSetActionHandler, {
              apply(target, receiver, argumentsList) {
                const [action, handler] = argumentsList;
                const result = Reflect.apply(target, session, argumentsList);
                if (typeof action === "string") {
                  if (typeof handler === "function") actionHandlers.set(action, handler);
                  else actionHandlers.delete(action);
                  queueMicrotask(() => post({}));
                }
                return result;
              }
            });
            try {
              Object.defineProperty(session, "setActionHandler", {
                configurable: true,
                value: observedSetActionHandler
              });
            } catch (_) {}
          }

          wrapProperty("metadata");
          wrapProperty("playbackState");

          const schedule = () => {
            if (scheduled) return;
            scheduled = true;
            setTimeout(() => { scheduled = false; post({}); }, 100);
          };
          const mediaEvents = ["play", "playing", "pause", "ended", "emptied", "volumechange", "loadedmetadata"];
          const observeMedia = event => {
            const media = event.target;
            if (!(media instanceof HTMLMediaElement)) return;
            if (["play", "playing"].includes(event.type)) didObservePlayback = true;
            if (event.type === "emptied" || event.type === "ended") qualifiedElements.delete(media);
            if (knownElements.size < 32 || knownElements.has(media)) knownElements.add(media);
            post({});
          };
          const observerOptions = { childList:true, subtree:true, attributes:true,
            attributeFilter:["controls", "src", "hidden", "inert", "aria-hidden", "role", "class", "style"] };
          const discover = root => {
            if (!root.querySelectorAll) return;
            currentPlayers();
            const inspect = element => {
              if (element instanceof HTMLMediaElement && knownElements.size < 32) {
                knownElements.add(element);
                if (!observedElements.has(element)) {
                  observedElements.add(element);
                  for (const type of mediaEvents) element.addEventListener(type, observeMedia);
                }
              }
              if (element.shadowRoot && !observedRoots.has(element.shadowRoot)) {
                observedRoots.add(element.shadowRoot);
                observer.observe(element.shadowRoot, observerOptions);
                discover(element.shadowRoot);
              }
            };
            inspect(root);
            let visited = 0;
            for (const element of root.querySelectorAll('*')) {
              if (++visited > 10000) break;
              inspect(element);
            }
          };
          const observer = new MutationObserver(records => {
            const hadMedia = knownElements.size > 0 || qualifiedElements.size > 0;
            for (const record of records) for (const node of record.addedNodes) discover(node);
            if (hadMedia || knownElements.size || qualifiedElements.size) schedule();
          });
          observer.observe(document, observerOptions);
          discover(document);
          for (const type of mediaEvents) document.addEventListener(type, observeMedia, { capture:true, passive:true });
          const observeInteraction = event => {
            if (!event.isTrusted || (event.type === 'keydown' && ![' ', 'Enter', 'k', 'K'].includes(event.key))) return;
            for (const media of knownElements) {
              let container = media;
              for (let depth = 0; container && depth < 4; depth++, container = parentOf(container)) {
                if (container === document.body || container === document.documentElement) break;
                if (event.composedPath().includes(container)) { interacted.add(media); break; }
              }
            }
            schedule();
          };
          document.addEventListener('pointerdown', observeInteraction, true);
          document.addEventListener('keydown', observeInteraction, true);
          for (const name of ['pushState', 'replaceState']) {
            const original = history[name];
            history[name] = function(...args) {
              const result = Reflect.apply(original, this, args);
              schedule();
              return result;
            };
          }
          addEventListener('popstate', schedule);
          addEventListener('hashchange', schedule);
          addEventListener('resize', schedule);
          document.addEventListener('visibilitychange', schedule);

          const bridge = Object.freeze({
            activate(identifier) {
              if (documentIdentifier !== identifier) {
                documentIdentifier = identifier;
                sequence = 0;
              }
              pageActive = true;
              post({});
            },
            emit() { post({}); },
            perform(action, expectedDocumentIdentifier) {
              if (expectedDocumentIdentifier !== documentIdentifier) return false;
              const players = currentPlayers();
              if (!pageActive || (!players.length && !hasExplicitNonElementPlayback())) return false;
              const handler = actionHandlers.get(action);
              if (typeof handler === "function") handler({ action });
              else if (action === "play" || action === "pause") {
                for (const element of players) {
                  if (action === "play") element.play()?.catch(() => {});
                  else element.pause();
                }
              } else return false;
              queueMicrotask(() => post({}));
              return true;
            },
            setMuted(muted, expectedDocumentIdentifier) {
              if (expectedDocumentIdentifier !== documentIdentifier) return false;
              const next = muted === true;
              let touched = false;
              if (!pageActive) return false;
              for (const element of currentPlayers()) {
                try {
                  element.muted = next;
                  touched = true;
                } catch (_) {}
              }
              queueMicrotask(() => post({}));
              return touched;
            }
          });
          Object.defineProperty(globalThis, "__crestMediaSessionBridge", {
            value: bridge,
            configurable: false,
            enumerable: false,
            writable: false
          });
          addEventListener("pagehide", () => {
            pageActive = false;
            artworkGeneration += 1;
            artworkAbortController?.abort();
            post({ invalidated: true, active: false });
          });
          addEventListener("pageshow", () => { pageActive = true; schedule(); });
          queueMicrotask(() => {
            refreshArtwork();
            post({});
          });
        })();
        """#
}

/// Shared DOM policy for recognizing an intentional player. PiP adds its own
/// presentation capability and viewport requirements; Now Playing also retains
/// paused and background playback while the same player still exists.
enum BrowserMediaPlayerPolicyScript {
    static let source = #"""
          const parentOf = element => element.parentElement || element.getRootNode()?.host;
          const isDecorative = video => {
            for (let element = video; element; element = parentOf(element)) {
              const style = getComputedStyle(element);
              if (element.hidden || element.inert || element.getAttribute('aria-hidden') === 'true'
                  || ['presentation', 'none'].includes(element.getAttribute('role'))
                  || style.display === 'none' || style.visibility !== 'visible'
                  || Number(style.opacity) === 0 || style.pointerEvents === 'none') return true;
            }
            return false;
          };
          const hasPlayerControls = (video, wasInteracted = false) => {
            if (video.controls) return true;
            const videoArea = video.getBoundingClientRect().width * video.getBoundingClientRect().height;
            let container = parentOf(video);
            for (let depth = 0; container && depth < 6; depth++, container = parentOf(container)) {
              if (container === document.body || container === document.documentElement) break;
              const bounds = container.getBoundingClientRect();
              if (bounds.width * bounds.height > Math.max(videoArea * 6, 4000000)) break;
              // A lone "pause background animation" control is deliberately not a
              // player. Seek/volume sliders plus transport buttons identify a real
              // control surface without depending on the language of its labels.
              const exposed = control => {
                for (let element = control; element && element !== container; element = parentOf(element)) {
                  if (element.hidden || getComputedStyle(element).display === 'none') return false;
                }
                return true;
              };
              const buttons = Array.from(container.querySelectorAll('button, [role="button"]')).filter(exposed);
              const timeline = Array.from(container.querySelectorAll('input[type="range"], [role="slider"], progress')).some(exposed);
              if (buttons.length >= 2 && timeline) return true;
              // Players without a seek bar (live streams) can qualify after a real
              // click/key interaction and with multiple actual playback controls.
              if (wasInteracted && buttons.length >= 2) {
                const controls = Array.from(buttons).filter(button =>
                  /play|pause|mute|volume|fullscreen/i.test(
                    [button.getAttribute('aria-label'), button.title, button.textContent].join(' ')
                  ));
                if (controls.length >= 2) return true;
              }
            }
            return false;
          };
        """#
}
