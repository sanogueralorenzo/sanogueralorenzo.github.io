import Foundation

extension PageOpened {
    @MainActor func apply(to state: CoreState) {
        state.publish(PageStateModel(page), forKey: page.id, into: \.pagesStorage, as: \.pages)
    }
}
