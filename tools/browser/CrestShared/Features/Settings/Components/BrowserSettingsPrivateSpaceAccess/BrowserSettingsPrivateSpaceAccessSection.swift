import SwiftUI

struct BrowserSettingsPrivateSpaceAccessSection: View {
    // MARK: - Variables

    let space: BrowserSpaceIdentity
    let accessController: BrowserSpaceAccessController
    let detail: String

    // MARK: - Initializers

    init(
        space: some BrowserSpaceIdentifying,
        accessController: BrowserSpaceAccessController,
        detail: String = "Unlock this Space to see its settings."
    ) {
        self.space = space.identity
        self.accessController = accessController
        self.detail = detail
    }

    // MARK: - Body

    var body: some View {
        Section {
            BrowserSettingsPrivateSpaceAccessRow(
                space: space,
                accessController: accessController
            )
        } header: {
            Text("Locked")
        } footer: {
            Text(detail).crestFormFootnote()
        }
        .accessibilityIdentifier("settings-private-space-lock")
    }
}
