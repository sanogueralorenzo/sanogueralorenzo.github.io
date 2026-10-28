import Foundation

struct BrowserUtilityListEmptyPresentation {
    let title: LocalizedStringResource
    let systemImage: String
    let description: LocalizedStringResource

    init(
        surface: BrowserUtilitySurface,
        searchText: String,
        filter: BrowserUtilityListFilter
    ) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        title =
            query.isEmpty
            ? surface.emptyTitle
            : BrowserUtilityPresentation.noResultsTitle
        systemImage = query.isEmpty ? surface.systemImage : "magnifyingglass"

        if !query.isEmpty {
            description = surface.noResultsDescription(matching: query)
        } else if filter.normalized(for: surface) != .all {
            description = BrowserUtilityPresentation.noFilteredItemsDescription
        } else {
            description = surface.emptyDescription
        }
    }
}
