import SwiftUI

struct MobileBrowserSettingsContent: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Binding var selection: BrowserSettingsDestination
    @Binding var searchText: String
    @Binding var path: [BrowserSettingsDestination]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.browserSettingsIsTab) private var isInTab

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                MobileBrowserRegularSettingsLayout(
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter,
                    selection: $selection,
                    searchText: $searchText,
                    dismiss: isInTab ? nil : { dismiss() }
                )
            } else {
                MobileBrowserCompactSettingsLayout(
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    dataDeleter: dataDeleter,
                    searchText: $searchText,
                    path: $path,
                    dismiss: isInTab ? nil : { dismiss() }
                )
            }
        }
        .presentationSizing(.fitted)
    }
}

struct MobileBrowserSettingsToolbar: ToolbarContent {
    let dismiss: (() -> Void)?

    var body: some ToolbarContent {
        if let dismiss {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: dismiss)
            }
        }
    }
}
