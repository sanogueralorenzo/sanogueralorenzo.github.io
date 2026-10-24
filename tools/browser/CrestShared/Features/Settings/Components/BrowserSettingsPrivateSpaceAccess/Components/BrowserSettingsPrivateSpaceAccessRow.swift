import SwiftUI

struct BrowserSettingsPrivateSpaceAccessRow: View {
    // MARK: - Variables

    let space: BrowserSpaceIdentity
    let accessController: BrowserSpaceAccessController

    // MARK: - Initializers

    init(space: some BrowserSpaceIdentifying, accessController: BrowserSpaceAccessController) {
        self.space = space.identity
        self.accessController = accessController
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            BrowserSettingsPrivateSpaceIdentity(space: space)
            Spacer(minLength: CrestSpacing.small)
            BrowserSettingsPrivateSpaceUnlockControl(
                space: space,
                accessController: accessController
            )
        }
        .frame(minHeight: CrestFormRowMetrics.minimumHeight)
        .accessibilityElement(children: .contain)
    }
}
