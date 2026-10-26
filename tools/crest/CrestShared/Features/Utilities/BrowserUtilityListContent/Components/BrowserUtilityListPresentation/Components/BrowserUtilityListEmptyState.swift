import SwiftUI

struct BrowserUtilityListEmptyState: View {
    let surface: BrowserUtilitySurface
    let searchText: String
    let filter: BrowserUtilityListFilter
    let dismiss: (() -> Void)?

    var body: some View {
        ContentUnavailableView(
            presentation.title,
            systemImage: presentation.systemImage,
            description: Text(presentation.description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(.rect)
        .onTapGesture {
            dismiss?()
        }
    }

    private var presentation: BrowserUtilityListEmptyPresentation {
        BrowserUtilityListEmptyPresentation(
            surface: surface,
            searchText: searchText,
            filter: filter
        )
    }
}

#if DEBUG
    #Preview("Empty and no search results") {
        VStack {
            BrowserUtilityListEmptyState(surface: .history, searchText: "", filter: .all, dismiss: nil)
            BrowserUtilityListEmptyState(surface: .downloads, searchText: "report", filter: .all, dismiss: nil)
        }.frame(width: 360, height: 420)
    }
#endif
