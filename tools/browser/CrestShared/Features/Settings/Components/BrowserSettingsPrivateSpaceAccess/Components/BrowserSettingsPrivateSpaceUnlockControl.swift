import SwiftUI

struct BrowserSettingsPrivateSpaceUnlockControl: View {
    let space: BrowserSpaceIdentity
    let accessController: BrowserSpaceAccessController

    var body: some View {
        if accessController.isAuthenticating(space) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Authenticating")
        } else {
            Button("Unlock", systemImage: "lock.open.fill") {
                Task { await accessController.unlock(space) }
            }
            .buttonStyle(.crestPrimary)
            .accessibilityLabel("Unlock \(space.name)")
        }
    }
}
