import Foundation

extension PageRemoved {
    @MainActor func apply(to state: CoreState) {
        state.publish(nil, forKey: pageID, into: \.pagesStorage, as: \.pages)
    }
}
