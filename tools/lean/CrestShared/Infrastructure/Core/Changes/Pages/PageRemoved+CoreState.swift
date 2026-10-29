import Foundation

extension PageRemoved {
    @MainActor func apply(to state: CoreState) {
        state.pageOrder.removeAll { $0 == pageID }
        state.publish(nil, forKey: pageID, into: \.pagesStorage, as: \.pages)
    }
}
