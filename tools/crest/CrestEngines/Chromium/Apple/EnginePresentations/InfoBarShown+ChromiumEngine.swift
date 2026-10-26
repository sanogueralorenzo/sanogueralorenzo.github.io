#if CREST_CHROMIUM_HOST
    import Foundation

    extension InfoBarShown {
        @MainActor func present(on engine: ChromiumEngine) {
            guard let page = engine.presentedPage(pageID),
                let bar = BrowserEngineInfoBar(
                    id: Int(infoBarID), message: message, acceptTitle: acceptLabel ?? "",
                    cancelTitle: cancelLabel ?? "",
                    isCloseable: closeable, isMinimizable: minimizable)
            else { return }
            page.observer(BrowserPageInfoBarAdded(bar: bar))
        }
    }
#endif
