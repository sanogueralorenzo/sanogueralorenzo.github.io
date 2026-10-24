#if CREST_CHROMIUM_HOST
    import AppKit

    extension PageThemeChanged {
        @MainActor func present(on engine: ChromiumEngine) {
            engine.presentedPage(pageID)?.observer(
                BrowserPageThemeColorChanged(
                    color: color.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }))
        }
    }
#endif
