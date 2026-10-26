import SwiftUI

struct BrowserUtilityListPresentation: View {
    let surface: BrowserUtilitySurface
    let searchText: String
    let filter: BrowserUtilityListFilter
    let presentationRequest: BrowserUtilityListRequest?
    let sections: [BrowserUtilityListSection]
    let downloads: [DownloadState]
    let actions: BrowserUtilityListActions
    let dismissOnBlankSpace: (() -> Void)?

    var body: some View {
        if let presentationRequest {
            if visibleSections.isEmpty {
                BrowserUtilityListEmptyState(
                    surface: surface,
                    searchText: searchText,
                    filter: filter,
                    dismiss: dismissOnBlankSpace
                )
            } else {
                BrowserUtilityListSectionList(
                    sections: visibleSections,
                    assignment: presentationRequest.assignment,
                    actions: actions,
                    dismissOnBlankSpace: dismissOnBlankSpace
                )
            }
        } else {
            BrowserUtilityListBlankState(dismiss: dismissOnBlankSpace)
        }
    }

    private var visibleSections: [BrowserUtilityListSection] {
        guard let presentationRequest else { return [] }
        return BrowserUtilityListReconciliation.sections(
            preparedSections: sections,
            surface: surface,
            assignment: presentationRequest.assignment,
            downloads: downloads,
            searchText: searchText,
            filter: filter
        )
    }
}
