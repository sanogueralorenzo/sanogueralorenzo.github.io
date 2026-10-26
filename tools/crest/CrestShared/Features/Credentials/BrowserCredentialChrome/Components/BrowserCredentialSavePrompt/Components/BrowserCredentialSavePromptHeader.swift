import SwiftUI

/// What the save prompt is about: the Space's key, what it will do, and the
/// account and origin it will do it for.
///
/// A pointer shell has room to answer in the same row, so its actions sit here
/// after the title. A touch shell puts them on a row of their own.
struct BrowserCredentialSavePromptHeader: View {
    let candidate: BrowserCredentialSaveCandidate
    let route: BrowserCredentialPromptRoute
    let space: BrowserSpaceIdentity?
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let perform: (BrowserCredentialPromptPrimaryAction) -> Void

    var body: some View {
        HStack(spacing: BrowserCredentialPromptMetrics.headerSpacing) {
            Image(
                systemName: candidate.passwordKind == .new
                    ? "key.horizontal.fill" : "key.fill"
            )
            .font(.title3)
            .foregroundStyle(space?.accent.tint.color ?? .accentColor)
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: BrowserCredentialPromptMetrics.headerTextSpacing
            ) {
                Text(route.title(spaceName: space?.name))
                    .font(.headline)
                Text("\(candidate.username) · \(candidate.origin.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if metrics.saveActionPlacement == .besideTitle {
                Spacer(
                    minLength: BrowserCredentialPromptMetrics
                        .saveHeaderSpacerLength
                )
                BrowserCredentialSaveActions(
                    route: route,
                    space: space,
                    metrics: metrics,
                    isStacked: false,
                    dismiss: dismiss,
                    perform: perform
                )
            }
        }
    }
}
