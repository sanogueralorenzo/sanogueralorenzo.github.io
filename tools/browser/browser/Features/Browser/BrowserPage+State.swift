import WebKit

extension BrowserPage {
    /// One collection pass feeds unload protection and media presentation.
    func refreshPageState() async {
        guard !isRetired, !refreshingPageState else { return }
        refreshingPageState = true
        defer { refreshingPageState = false }
        let script = #"""
            const media = [...document.querySelectorAll('video,audio')].some(e => !e.paused && !e.ended);
            const dirty = [...document.querySelectorAll('input,textarea,select,[contenteditable=true]')].some(e =>
              (!e.isContentEditable && (e.type === 'checkbox' || e.type === 'radio' ? e.checked !== e.defaultChecked :
              e.tagName === 'SELECT' ? [...e.options].some(o => o.selected !== o.defaultSelected) : e.value !== e.defaultValue)));
            const e = document.querySelector('video,audio');
            return {playing:media, hasMedia:!!e, muted:e?.muted || false, dirty, title:navigator.mediaSession?.metadata?.title || document.title,
              artist:navigator.mediaSession?.metadata?.artist || '', duration: Number.isFinite(e?.duration) ? e.duration : 0,
              elapsed:Number.isFinite(e?.currentTime) ? e.currentTime : 0};
            """#
        let revision = documentRevision
        guard
            var value = try? await webView.callAsyncJavaScript(
                script, arguments: [:], in: nil, contentWorld: .defaultClient)
                as? [String: Any], !isRetired
        else { return }
        var dirty = value["dirty"] as? Bool != false
        mediaFrame = nil
        if value["playing"] as? Bool != true {
            for frame in Array(siteController?.frames.values ?? [:].values).filter({ !$0.isMainFrame }).prefix(32) {
                guard
                    let child = try? await webView.callAsyncJavaScript(
                        script, arguments: [:], in: frame, contentWorld: .defaultClient) as? [String: Any],
                    revision == documentRevision
                else { continue }
                dirty = dirty || child["dirty"] as? Bool != false
                if child["playing"] as? Bool == true
                    || (value["hasMedia"] as? Bool != true && child["hasMedia"] as? Bool == true)
                {
                    value = child
                    mediaFrame = frame
                    if child["playing"] as? Bool == true { break }
                }
            }
        }
        guard revision == documentRevision else { return }
        let native = await withCheckedContinuation { continuation in
            webView.requestMediaPlaybackState { continuation.resume(returning: $0) }
        }
        guard revision == documentRevision, !isRetired else { return }
        documentHasEdits = dirty
        updateEditProtection()
        await updateMediaState(value, native: native, revision: revision)
    }
}
