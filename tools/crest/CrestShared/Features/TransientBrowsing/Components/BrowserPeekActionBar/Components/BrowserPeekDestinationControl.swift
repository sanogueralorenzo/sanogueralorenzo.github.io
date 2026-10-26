import SwiftUI

struct BrowserPeekDestinationControl: View {
    // MARK: - Static Variables

    private static let separatorOpacity = 0.16
    private static let separatorWidth: CGFloat = 0.5
    private static let separatorHeight: CGFloat = 22

    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let openInSpace: (BrowserSpaceRuntimeAssignment) -> Void

    private var selectedSpace: BrowserSpaceIdentity? {
        spaces.first { $0.id == selectedSpaceID }
    }

    private var spaceTint: Color {
        selectedSpace?.branding.backgroundColor.color ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 0) {
            BrowserPeekDestinationPrimaryButton(
                selectedSpace: selectedSpace,
                openInSelectedSpace: openInSelectedSpace
            )

            Rectangle()
                .fill(.primary.opacity(Self.separatorOpacity))
                .frame(
                    width: Self.separatorWidth,
                    height: Self.separatorHeight
                )
                .accessibilityHidden(true)

            BrowserPeekDestinationMenu(
                spaces: spaces,
                selectedSpace: selectedSpace,
                openInSpace: openInSpace
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: BrowserPeekActionBar.controlHeight)
        .browserReadableForeground(over: spaceTint)
        .contentShape(.capsule)
        .glassEffect(
            .regular.tint(spaceTint).interactive(),
            in: .capsule
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-space-control")
    }

    private func openInSelectedSpace() {
        guard let selectedSpace else { return }
        openInSpace(selectedSpace.assignment)
    }
}
