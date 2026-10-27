import WebKit

extension BrowserPage {
    static let mediaActionScript = #"""
        (() => {
          if(!navigator.mediaSession || globalThis.__leanMediaActions) return;
          const actions = new Map(); const original = navigator.mediaSession.setActionHandler.bind(navigator.mediaSession);
          navigator.mediaSession.setActionHandler = (action, handler) => { actions.set(action,handler); return original(action,handler); };
          Object.defineProperty(globalThis,'__leanMediaActions',{value:actions,configurable:false});
        })();
        """#

    func performMediaAction(_ action: String, time: Double? = nil) {
        let script = #"""
            const callback = globalThis.__leanMediaActions?.get(action);
            if(callback) { callback({action,seekTime:time,seekOffset:10,fastSeek:false}); return; }
            const e = document.querySelector('video,audio'); if(!e) return;
            if(action === 'play') await e.play(); else if(action === 'pause') e.pause();
            else if(action === 'seekto') e.currentTime = Math.max(0,time);
            else if(action === 'seekforward') e.currentTime = Math.min(e.duration,e.currentTime+10);
            else if(action === 'seekbackward') e.currentTime = Math.max(0,e.currentTime-10);
            """#
        Task {
            _ = try? await webView.callAsyncJavaScript(
                script, arguments: ["action": action, "time": time ?? 0],
                in: mediaFrame, contentWorld: .page)
            await readMediaState()
            owner?.owner.media?.refresh()
        }
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
