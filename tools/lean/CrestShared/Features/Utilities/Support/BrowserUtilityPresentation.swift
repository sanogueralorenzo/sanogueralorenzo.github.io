import Foundation

enum BrowserUtilityPresentation {
    static let noResultsTitle: LocalizedStringResource = "No Results"
    static let noFilteredItemsDescription: LocalizedStringResource =
        "No items match the selected filter."
    static let selected: LocalizedStringResource = "Selected"
    static let notSelected: LocalizedStringResource = "Not selected"

    static func downloadCount(_ count: Int) -> LocalizedStringResource {
        "\(max(count, 0)) downloads"
    }

    static func historyVisits(
        host: String,
        count: Int
    ) -> LocalizedStringResource {
        "\(host) · \(max(count, 0)) visits"
    }
}
