import Foundation

extension SearchCatalogChanged {
    /// The core publishes the device's search catalog whole.
    @MainActor func apply(to state: CoreState) {
        state.searchCatalog = self
    }
}
