import Foundation

extension SearchProvider: Identifiable {
    // MARK: - Variables

    var id: String {
        name
    }

    /// The palette's action for this engine.
    var actionTitle: String {
        String(localized: "Search \(title)", comment: "A palette row that searches a search engine.")
    }
}
