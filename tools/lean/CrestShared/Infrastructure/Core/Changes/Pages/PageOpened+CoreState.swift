import Foundation

extension PageOpened {
    @MainActor func apply(to state: CoreState) {
        if state.pages[page.id] == nil { state.pageOrder.append(page.id) }
        state.publish(PageStateModel(page), forKey: page.id, into: \.pagesStorage, as: \.pages)
    }
}
