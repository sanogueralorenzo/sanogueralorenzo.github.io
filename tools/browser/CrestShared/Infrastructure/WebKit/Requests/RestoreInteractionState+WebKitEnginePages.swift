import Foundation

extension RestoreInteractionState {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.page(pageID)?.engine.restoreHistory(state) ?? false
    }
}
