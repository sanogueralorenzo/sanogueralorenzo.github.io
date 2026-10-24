import Foundation

extension ReloadPage {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        let reloaded = pages.page(pageID)
        reloaded?.engine.reload(bypassingCache: bypassesCache)
        return reloaded != nil
    }
}
