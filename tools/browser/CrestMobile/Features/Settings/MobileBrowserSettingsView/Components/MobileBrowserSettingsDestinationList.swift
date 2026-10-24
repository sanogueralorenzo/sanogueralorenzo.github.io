import SwiftUI

struct MobileBrowserSettingsDestinationList: View {
    @Binding var selection: BrowserSettingsDestination
    @Binding var searchText: String
    /// The read model whose engines say which destinations exist.
    let state: CoreState

    @Environment(\.locale) private var locale

    // Rows are buttons rather than the list's own selection: a selection
    // list inside the browser's page surface never receives the tap.
    var body: some View {
        List {
            Section {
                MobileSettingsBuildHeader()
            }
            Section {
                ForEach(filteredDestinations) { destination in
                    Button {
                        selection = destination
                    } label: {
                        MobileSettingsDestinationRow(destination: destination)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-\(destination.name)")
                    .listRowBackground(rowBackground(for: destination))
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
        }
        .listStyle(.sidebar)
        .listRowSpacing(4)
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 290)
        .searchable(text: $searchText, prompt: "Search settings")
    }

    private var filteredDestinations: [BrowserSettingsDestination] {
        MobileSettingsDestinationFilter.destinations(
            matching: searchText,
            locale: locale,
            in: state
        )
    }

    /// The system's own fill behind the row that's showing.
    private func rowBackground(for destination: BrowserSettingsDestination) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(selection == destination ? Color(uiColor: .systemFill) : .clear)
            .padding(.vertical, 2)
    }
}
