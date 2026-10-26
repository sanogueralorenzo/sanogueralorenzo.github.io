import SwiftUI

struct BrowserCredentialSavePromptContent: View {
    let candidate: BrowserCredentialSaveCandidate
    let route: BrowserCredentialPromptRoute
    let destination: BrowserCredentialPromptDestinationMetadata
    let space: BrowserSpaceIdentity?
    let namesSystemPasswordsDestination: Bool
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let perform: (BrowserCredentialPromptPrimaryAction) -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialPromptMetrics.savePromptContentSpacing
        ) {
            BrowserCredentialSavePromptHeader(
                candidate: candidate,
                route: route,
                space: space,
                metrics: metrics,
                dismiss: dismiss,
                perform: perform
            )

            BrowserCredentialSaveDestination(
                destination: destination,
                space: space,
                namesSystemPasswordsDestination: namesSystemPasswordsDestination
            )

            if candidate.isCrossOriginFrame {
                Text(
                    route.crossOriginMessage(
                        frameOrigin: candidate.origin,
                        topLevelOrigin: candidate.topLevelOrigin,
                        subject: metrics.saveCrossOriginSubject
                    )
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let errorMessage = route.errorMessage(spaceName: space?.name) {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if metrics.saveActionPlacement == .belowContent {
                BrowserCredentialSaveActionRow(
                    route: route,
                    space: space,
                    metrics: metrics,
                    dismiss: dismiss,
                    perform: perform
                )
            }
        }
    }
}
