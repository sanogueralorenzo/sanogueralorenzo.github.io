import Foundation

enum BrowserPictureInPictureScript {
    static let source = #"""
        (() => {
          'use strict';
          if (globalThis.__crestPictureInPicture) return;
          const handler = globalThis.webkit?.messageHandlers?.crestPictureInPicture;
          if (!handler) return;
          const documentID = crypto.randomUUID?.() || `${Date.now()}-${Math.random()}`;
          const ids = new WeakMap();
          const interacted = new WeakSet();
          const knownVideos = new Set();
          const knownFrames = new Set();
          const interestedFrames = new Set();
          const frameVisibility = new WeakMap();
          const observedRoots = new WeakSet();
          const roots = new Set([document]);
          const pendingRoots = new Set();
          let discoveryTimer = null;
          let observesAttributes = false;
          let reportedInterest = false;
          let publishedActive = false;
          let nextID = 0;
          let scheduled = false;
          let lastState = '';
          let automatic = null;
          let parentAllows = window === top;
          const idFor = video => {
            if (!ids.has(video)) {
              ids.set(video, String(++nextID));
              for (const type of ['playing', 'pause', 'ended', 'emptied', 'loadedmetadata', 'resize',
                                  'enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged']) {
                video.addEventListener(type, schedule);
              }
              video.addEventListener('leavepictureinpicture', () => {
                if (automatic?.video === video) automatic = null;
              });
            }
            return ids.get(video);
          };
          const send = payload => handler.postMessage({ documentID, ...payload });
          const connected = elements => {
            for (const element of elements) if (!element.isConnected) elements.delete(element);
            return Array.from(elements);
          };
          const videos = () => connected(knownVideos);
          \#(BrowserMediaPlayerPolicyScript.source)
          const potentiallyPlayable = video => !video.paused && !video.ended && video.readyState >= 2
            && video.videoWidth > 0 && video.videoHeight > 0
            && !video.disablePictureInPicture && !video.controlsList?.contains('nopictureinpicture');
          const hasInterest = () => videos().some(video => potentiallyPlayable(video) || isActive(video))
            || connected(interestedFrames).length > 0;
          const reportInterest = () => {
            const interested = hasInterest();
            if (window === top || interested === reportedInterest) return;
            reportedInterest = interested;
            parent.postMessage({ crestPiPFrame: 'interest', interested }, '*');
          };
          const candidate = video => {
            const videoID = idFor(video);
            // Layout reads can synchronously flush an otherwise unrelated page
            // mutation. A paused, unloaded or disallowed player needs none.
            if (!parentAllows || !potentiallyPlayable(video)) return { videoID, eligible: false, score: 0 };
            const bounds = video.getBoundingClientRect();
            const inViewport = bounds.bottom > 0 && bounds.right > 0
              && bounds.top < innerHeight && bounds.left < innerWidth;
            const eligible = bounds.width >= 160 && bounds.height >= 90 && inViewport
              && video.webkitSupportsPresentationMode?.('picture-in-picture') === true
              && !isDecorative(video) && hasPlayerControls(video, interacted.has(video));
            return { videoID, eligible,
              score: bounds.width * bounds.height + (interacted.has(video) ? 100000000 : 0) };
          };
          const isActive = video => document.pictureInPictureElement === video
            || video.webkitPresentationMode === 'picture-in-picture';
          const snapshot = () => {
            flushDiscovery();
            const found = videos();
            const candidates = found.map(candidate).filter(item => item.eligible)
              .sort((a, b) => b.score - a.score);
            return { kind: 'state', ...candidates[0], eligible: candidates.length > 0,
              active: found.some(isActive) };
          };
          const publish = (refreshFrames = false) => {
            scheduled = false;
            flushDiscovery();
            reportInterest();
            publishFrameEligibility(refreshFrames);
            const state = snapshot();
            publishedActive = state.eligible || state.active;
            const encoded = JSON.stringify(state);
            if (encoded === lastState) return;
            lastState = encoded;
            send(state);
          };
          const schedule = () => {
            reportInterest();
            if (!hasInterest() && !publishedActive) return;
            if (scheduled) return;
            scheduled = true;
            setTimeout(publish, 100);
          };
          // The parent can see whether an iframe is decorative; a cross-origin
          // child cannot inspect that DOM. Propagate only this boolean, never media
          // URLs or page contents. Each hop validates the sending Window identity.
          const publishFrameEligibility = (refresh = false) => {
            for (const frame of connected(interestedFrames)) {
              const bounds = frame.getBoundingClientRect();
              const allowed = parentAllows && !isDecorative(frame)
                && bounds.width >= 160 && bounds.height >= 90
                && bounds.bottom > 0 && bounds.right > 0
                && bounds.top < innerHeight && bounds.left < innerWidth;
              if (!refresh && frameVisibility.get(frame) === allowed) continue;
              frameVisibility.set(frame, allowed);
              frame.contentWindow?.postMessage({ crestPiPFrame: 'visibility', allowed, refresh }, '*');
            }
          };
          addEventListener('message', event => {
            if (event.data?.crestPiPFrame === 'visibility' && window !== top && event.source === parent) {
              const allowed = event.data.allowed === true;
              if (parentAllows === allowed && event.data.refresh !== true) return;
              parentAllows = allowed;
              if (event.data.refresh === true) { lastState = ''; publish(true); return; }
              schedule();
            }
            if (event.data?.crestPiPFrame === 'interest') {
              if (event.data.interested === true) flushDiscovery();
              const frame = connected(knownFrames).find(frame => frame.contentWindow === event.source);
              if (!frame) return;
              if (event.data.interested === true) interestedFrames.add(frame);
              else interestedFrames.delete(frame);
              frameVisibility.delete(frame);
              updateObservation();
              schedule();
            }
          });
          const cancel = requestID => {
            if (automatic?.requestID !== requestID) return;
            automatic.cancelled = true;
            if (isActive(automatic.video)) automatic.video.webkitSetPresentationMode('inline');
          };
          const enter = (expectedDocumentID, videoID, requestID) => {
            if (expectedDocumentID !== documentID || document.pictureInPictureElement) return false;
            const video = videos().find(video => idFor(video) === videoID);
            if (!video || !candidate(video).eligible) return false;
            const request = { requestID, video, cancelled: false };
            automatic = request;
            try {
              video.requestPictureInPicture().then(() => {
                if (request.cancelled) {
                  video.webkitSetPresentationMode('inline');
                  return;
                }
                send({ kind: 'request', requestID, succeeded: true });
                publish();
              }, () => send({ kind: 'request', requestID, succeeded: false }));
              return true;
            } catch (_) { return false; }
          };
          const observeInteraction = event => {
            if (!event.isTrusted || (event.type === 'keydown' && ![' ', 'Enter', 'k', 'K'].includes(event.key))) return;
            for (const video of videos()) {
              let container = video;
              for (let depth = 0; container && depth < 4; depth++, container = parentOf(container)) {
                if (container === document.body || container === document.documentElement) break;
                if (event.composedPath().includes(container)) { interacted.add(video); break; }
              }
            }
            schedule();
          };
          const observeMedia = event => {
            if (!(event.target instanceof HTMLVideoElement)) return;
            if (knownVideos.size < 32) knownVideos.add(event.target);
            idFor(event.target);
            updateObservation();
            schedule();
          };
          for (const type of ['playing', 'pause', 'ended', 'emptied', 'loadedmetadata', 'resize',
                              'enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged']) {
            document.addEventListener(type, observeMedia, true);
          }
          document.addEventListener('pointerdown', observeInteraction, true);
          document.addEventListener('keydown', observeInteraction, true);
          document.addEventListener('visibilitychange', () => { lastState = ''; schedule(); });
          addEventListener('resize', schedule);
          addEventListener('scroll', schedule, { passive: true, capture: true });
          addEventListener('pageshow', () => { lastState = ''; schedule(); });
          addEventListener('pagehide', () => send({ kind: 'removed' }));
          // Keep discovery cheap on documents without media, including app-like
          // pages that continually rebuild DOM. Scan coalesced inserted subtrees
          // outside mutation delivery; media events and explicit entry/refresh
          // can discover a player immediately when necessary.
          const observerOptions = { subtree: true, attributes: true,
            attributeFilter: ['controls', 'autoplay', 'loop', 'muted', 'hidden', 'aria-hidden',
                             'disablepictureinpicture', 'role', 'class', 'style'] };
          const discover = (root, scannedRoots = new WeakSet()) => {
            if (!root.querySelectorAll) return;
            // A batch can report both an inserted ancestor and its descendants.
            // Their current subtrees already include every change in the batch.
            for (let ancestor = root; ancestor; ancestor = ancestor.parentNode) {
              if (scannedRoots.has(ancestor)) return;
            }
            connected(knownVideos);
            connected(knownFrames);
            const inspect = element => {
              if (element.matches?.('video') && knownVideos.size < 32) knownVideos.add(element);
              if (element.matches?.('iframe') && knownFrames.size < 64) knownFrames.add(element);
              if (element.shadowRoot && !roots.has(element.shadowRoot)) {
                roots.add(element.shadowRoot);
                mutationObserver.observe(element.shadowRoot, { childList: true, subtree: true });
                if (!observedRoots.has(element.shadowRoot)) {
                  observedRoots.add(element.shadowRoot);
                  element.shadowRoot.addEventListener('playing', observeMedia, true);
                }
                if (observesAttributes) attributeObserver.observe(element.shadowRoot, observerOptions);
                discover(element.shadowRoot, scannedRoots);
              }
            };
            inspect(root);
            // A deferred scan may first encounter a shadow root after a large
            // subtree was inserted. Find its media even beyond the bounded
            // general walk used to discover further open shadow roots.
            for (const element of root.querySelectorAll('video, iframe')) inspect(element);
            let visited = 0;
            const elements = root.querySelectorAll('*');
            for (const element of elements) {
              if (++visited > 10000) break;
              inspect(element);
            }
            // A truncated scan must not suppress later records beyond its limit.
            if (elements.length <= 10000) scannedRoots.add(root);
          };
          const updateObservation = () => {
            let removedRoot = false;
            for (const root of roots) {
              if (root !== document && !root.host?.isConnected) { roots.delete(root); removedRoot = true; }
            }
            const needed = connected(knownVideos).length > 0 || connected(interestedFrames).length > 0;
            if (needed === observesAttributes && !removedRoot) return;
            observesAttributes = needed;
            attributeObserver.disconnect();
            if (!needed) return;
            for (const root of roots) {
              attributeObserver.observe(root, observerOptions);
            }
          };
          const flushDiscovery = () => {
            if (discoveryTimer !== null) clearTimeout(discoveryTimer);
            discoveryTimer = null;
            if (!pendingRoots.size) return;
            const scannedRoots = new WeakSet();
            for (const root of pendingRoots) if (root.isConnected) discover(root, scannedRoots);
            pendingRoots.clear();
            updateObservation();
          };
          const queueDiscovery = node => {
            if (node.nodeType !== Node.ELEMENT_NODE) return;
            if (pendingRoots.has(document)) return;
            if (pendingRoots.size >= 256) { pendingRoots.clear(); pendingRoots.add(document); }
            else pendingRoots.add(node);
            if (discoveryTimer !== null) return;
            discoveryTimer = setTimeout(() => { flushDiscovery(); schedule(); }, 100);
          };
          const attributeObserver = new MutationObserver(schedule);
          const mutationObserver = new MutationObserver(records => {
            for (const record of records) for (const node of record.addedNodes) queueDiscovery(node);
            updateObservation();
            schedule();
          });
          mutationObserver.observe(document, { childList: true, subtree: true });
          discover(document);
          updateObservation();
          globalThis.__crestPictureInPicture = Object.freeze({ enter, cancel, snapshot,
            emit() { lastState = ''; publish(true); } });
          if (window !== top) parent.postMessage({ crestPiPFrame: 'interest', interested: false }, '*');
          schedule();
        })();
        """#
}
