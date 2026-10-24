import SwiftUI

struct MobileBrowserCompactSettingsLayout: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Binding var searchText: String
    @Binding var path: [BrowserSettingsDestination]
    let dismiss: (() -> Void)?

    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    MobileSettingsBuildHeader()
                }
                Section {
                    ForEach(filteredDestinations) { destination in
                        NavigationLink(value: destination) {
                            MobileSettingsDestinationRow(destination: destination)
                        }
                        .accessibilityIdentifier("settings-\(destination.name)")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { MobileBrowserSettingsToolbar(dismiss: dismiss) }
            .searchable(text: $searchText, prompt: "Search settings")
            .navigationDestination(for: BrowserSettingsDestination.self) {
                destination in
                MobileBrowserSettingsDestinationPage(
                    destination: destination,
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter
                )
                .navigationTitle(Text(destination.title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { MobileBrowserSettingsToolbar(dismiss: dismiss) }
            }
        }
    }

    private var filteredDestinations: [BrowserSettingsDestination] {
        MobileSettingsDestinationFilter.destinations(
            matching: searchText,
            locale: locale,
            in: browser.core.state
        )
    }
}
