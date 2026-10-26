import SwiftUI

/// The title row a credential fill prompt opens with: the site's mark, what the
/// prompt is for, the origin it was asked from, and the way out.
struct BrowserCredentialPromptHeader: View {
    let kind: BrowserCredentialPromptHeaderKind
    let request: BrowserCredentialFillRequest
    let space: BrowserSpaceIdentity?
    let siteIconData: Data?
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: BrowserCredentialPromptMetrics.headerSpacing) {
            BrowserCredentialPromptIdentity(
                kind: kind,
                iconData: siteIconData,
                showsSiteIcon: !request.isCrossOriginFrame,
                tint: space?.accent.tint.color ?? .accentColor
            )
            VStack(
                alignment: .leading,
                spacing: BrowserCredentialPromptMetrics.headerTextSpacing
            ) {
                Text(kind.title(space?.name ?? "this Space"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(request.origin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: BrowserCredentialPromptMetrics.headerSpacerLength)
            Button("Close", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(
                    width: metrics.closeControlSize,
                    height: metrics.closeControlSize
                )
                .contentShape(.rect)
        }
    }
}
