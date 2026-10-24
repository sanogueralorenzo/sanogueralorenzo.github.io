import Foundation

extension SaveInteractionState {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        InteractionState(state: pages.page(pageID)?.engine.savedHistory())
    }
}
