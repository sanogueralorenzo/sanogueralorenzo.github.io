import Foundation

extension PageChanged {
    /// A page that stays open keeps its object, which notifies only for what
    /// really changed. The core publishes a page's `PageOpened` before any
    /// change to it, so a change for a page the state does not hold is about
    /// one already removed and changes nothing.
    @MainActor func apply(to state: CoreState) {
        state.pages[self.page.id]?.update(self.page)
    }

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        // Read before the change lands: whether it moves the page to another engine.
        if let before = core.state.pages[page.id]?.engine, before != page.engine {
            batch.movedPages.append(page.id)
        }
        apply(to: core.state)
    }
}
