import SwiftUI

/// Where the password is about to go, said before it goes there.
struct BrowserCredentialSaveDestination: View {
    let destination: BrowserCredentialPromptDestinationMetadata
    let space: BrowserSpaceIdentity?
    let namesSystemPasswordsDestination: Bool

    var body: some View {
        HStack(spacing: BrowserCredentialPromptMetrics.destinationSpacing) {
            detail
            if let syncStatus = destination.syncStatus {
                Text("·")
                Label(syncStatus, systemImage: "icloud")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// The Space's own crest, unless the sentence beside it is already about
    /// iCloud, or there is no Space to draw.
    @ViewBuilder
    private var detail: some View {
        if namesSystemPasswordsDestination {
            Label(destination.detail, systemImage: "icloud")
        } else if let space {
            BrowserSpaceIdentityLabel(
                space: space,
                title: String(localized: destination.detail),
                iconSize: BrowserCredentialPromptMetrics.destinationIconSize
            )
        } else {
            Label(destination.detail, systemImage: "square.grid.2x2")
        }
    }
}
