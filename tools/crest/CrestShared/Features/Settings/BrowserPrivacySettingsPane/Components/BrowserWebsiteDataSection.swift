import SwiftUI

/// The sites that keep data in a Space, with Remove for one and Remove All.
struct BrowserWebsiteDataSection: View {
    /// The Space's sites, or nil until the pane asks for them.
    let list: BrowserWebsiteDataList?
    let spaceName: String

    @State private var query = ""
    @State private var confirmsRemoveAll = false

    var body: some View {
        Section("Website data") {
            if let list, let sites = list.sites {
                if sites.isEmpty, list.isComplete {
                    Text("No website data")
                        .foregroundStyle(.secondary)
                } else {
                    // Remove All also clears what an engine could not list.
                    if !sites.isEmpty {
                        BrowserCredentialSearchField(
                            title: "Search Websites", text: $query, accessibilityIdentifier: "website-data-search")
                        ForEach(list.sites(matching: query), id: \.site) { site in
                            BrowserWebsiteDataRow(site: site, isRemoving: list.isRemoving) {
                                Task { await list.remove([site]) }
                            }
                        }
                    }
                    HStack {
                        if list.removalFailed {
                            Label("Some data couldn’t be removed", systemImage: "exclamationmark.triangle")
                                .font(CrestTypography.metadata)
                                .foregroundStyle(CrestColor.textSecondary)
                        }
                        Spacer()
                        Button("Remove All…", role: .destructive) { confirmsRemoveAll = true }
                            .disabled(list.isRemoving)
                    }
                }
                if !list.isComplete {
                    Text("Some sites may be missing.")
                        .font(CrestTypography.metadata)
                        .foregroundStyle(CrestColor.textSecondary)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(
            "Remove all website data in “\(spaceName)”?",
            isPresented: $confirmsRemoveAll,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                guard let list else { return }
                Task { await list.removeAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll be signed out of every site in this Space.")
        }
    }
}
