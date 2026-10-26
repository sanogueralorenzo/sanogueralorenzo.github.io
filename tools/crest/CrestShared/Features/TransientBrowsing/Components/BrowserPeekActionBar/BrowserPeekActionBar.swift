import SwiftUI

struct BrowserPeekActionBar: View {
    // MARK: - Static Variables

    static let controlHeight: CGFloat = 48
    private static let closeControlWidth: CGFloat = 206
    private static let openControlWidth: CGFloat = 206
    private static let controlSpacing: CGFloat = 10

    static var width: CGFloat {
        closeControlWidth + controlSpacing + openControlWidth
    }

    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let closeAccessibilityLabel: LocalizedStringKey
    let closeHelp: LocalizedStringKey
    let dismiss: () -> Void
    let openInSpace: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        GlassEffectContainer(spacing: Self.controlSpacing) {
            HStack(spacing: Self.controlSpacing) {
                BrowserPeekCloseButton(
                    accessibilityLabel: closeAccessibilityLabel,
                    help: closeHelp,
                    dismiss: dismiss
                )

                BrowserPeekDestinationControl(
                    spaces: spaces,
                    selectedSpaceID: selectedSpaceID,
                    openInSpace: openInSpace
                )
            }
            .labelStyle(.titleAndIcon)
        }
    }
}
