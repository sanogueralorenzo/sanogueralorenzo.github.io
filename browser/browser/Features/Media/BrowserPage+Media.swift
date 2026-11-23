import WebKit

extension BrowserPage {
    func updateMediaState(_ value: [String: Any], native: WKMediaPlaybackState, revision: Int) async {
        isPlaying =
            value["playing"] as? Bool == true
            || (native == .playing && value["hasMedia"] as? Bool != true)
        let nextTitle = value["title"] as? String ?? title
        if mediaTitle != nextTitle { nowPlayingHidden = false }
        mediaTitle = nextTitle
        hasMedia = isPlaying || value["hasMedia"] as? Bool == true
        mediaIsMuted = value["muted"] as? Bool == true
        let actions =
            try? await webView.callAsyncJavaScript(
                "return [...(globalThis.__browserMediaActions || new Map())].filter(([key,value]) => typeof value === 'function').map(([key]) => key)",
                arguments: [:], in: mediaFrame, contentWorld: .page) as? [String]
        guard revision == documentRevision, !isRetired else { return }
        mediaActions = Set(actions ?? [])
        if hasMedia { mediaActions.formUnion(["play", "pause"]) }
        mediaArtist = value["artist"] as? String ?? ""
        mediaDuration = value["duration"] as? Double ?? 0
        mediaElapsed = value["elapsed"] as? Double ?? 0
    }

    func beginPictureInPicture() { pictureInPicture?.leaveTab() }

    static let mediaActionScript = #"""
        (() => {
          if(!navigator.mediaSession || globalThis.__browserMediaActions) return;
          const actions = new Map(); const original = navigator.mediaSession.setActionHandler.bind(navigator.mediaSession);
          navigator.mediaSession.setActionHandler = (action, handler) => { actions.set(action,handler); return original(action,handler); };
          Object.defineProperty(globalThis,'__browserMediaActions',{value:actions,configurable:false});
        })();
        """#

    func performMediaAction(_ action: String, time: Double? = nil) {
        let script = #"""
            const callback = globalThis.__browserMediaActions?.get(action);
            if(callback) { callback({action,seekTime:time,seekOffset:10,fastSeek:false}); return; }
            const e = document.querySelector('video,audio'); if(!e) return;
            if(action === 'play') await e.play(); else if(action === 'pause') e.pause();
            else if(action === 'mute') e.muted=true; else if(action === 'unmute') e.muted=false;
            else if(action === 'seekto') e.currentTime = Math.max(0,time);
            else if(action === 'seekforward') e.currentTime = Math.min(e.duration,e.currentTime+10);
            else if(action === 'seekbackward') e.currentTime = Math.max(0,e.currentTime-10);
            """#
        Task {
            _ = try? await webView.callAsyncJavaScript(
                script, arguments: ["action": action, "time": time ?? 0],
                in: mediaFrame, contentWorld: .page)
            await refreshPageState()
            sessionOwner?.media?.refresh()
        }
    }

    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange active: Bool) {
        hasPictureInPicture = active
        pictureInPicture?.nativePresentationDidChange(isActive: active)
    }

    @objc(_webViewFullscreenMayReturnToInline:)
    func restorePictureInPicture(_ view: WKWebView) {
        guard view === webView, pictureInPicture?.canRestoreSource == true, let owner else { return }
        var context = owner
        if owner.isClosed {
            owner.owner.openWindow?(BrowserWindowState(spaceID: spaceID))
            guard let id = owner.owner.activeWindowID, let reopened = owner.owner.contexts[id] else { return }
            context = reopened
        }
        context.selectTab(id)
        context.window?.makeKeyAndOrderFront(nil)
    }
}
