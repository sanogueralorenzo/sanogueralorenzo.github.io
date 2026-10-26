import SwiftUI

struct BrowserPeekDestinationPrimaryButton: View {
    // MARK: - Static Variables

    private static let leadingInset: CGFloat = 16
    private static let contentSpacing = CrestSpacing.small
    private static let iconSize: CGFloat = 22
    private static let title = "Open In…"

    // MARK: - Variables

    let selectedSpace: BrowserSpaceIdentity?
    let openInSelectedSpace: () -> Void

    var body: some View {
        Button(action: openInSelectedSpace) {
            HStack(spacing: Self.contentSpacing) {
                if let selectedSpace {
                    BrowserSpaceIdentityIcon(
                        identity: selectedSpace,
                        size: Self.iconSize
                    )
                } else {
                    Image(systemName: "square.grid.2x2")
                }
                Text(Self.title)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, Self.leadingInset)
            .frame(height: BrowserPeekActionBar.controlHeight)
            .contentShape(.rect)
        }
        .keyboardShortcut("o", modifiers: .command)
        .accessibilityLabel(Text(Self.title))
        .accessibilityValue(Text(selectedSpace?.name ?? "Space"))
        .accessibilityIdentifier("peek-open-selected-space")
        .help("Open in \(selectedSpace?.name ?? "Space") (⌘O)")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserPeekDestinationPrimaryButton(
            selectedSpace: BrowserSpaceBrandingPreviewFixture.simpleSpace.identity, openInSelectedSpace: {}
        ).padding()
    }
#endif
