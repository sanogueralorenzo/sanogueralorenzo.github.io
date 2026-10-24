import SwiftUI

struct BrowserPeekDestinationMenu: View {
    // MARK: - Static Variables

    private static let width: CGFloat = 48

    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpace: BrowserSpaceIdentity?
    let openInSpace: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        Menu {
            ForEach(spaces) { candidate in
                Button {
                    openInSpace(candidate.assignment)
                } label: {
                    BrowserSpaceIdentityLabel(
                        identity: candidate,
                        title: candidate.name
                    )
                }
            }
            .crestMenuActionLabelStyle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .frame(
                    width: Self.width,
                    height: BrowserPeekActionBar.controlHeight
                )
                .contentShape(.rect)
        }
        .crestMenuActionLabelStyle()
        .menuIndicator(.hidden)
        .accessibilityLabel("Choose Destination Space")
        .accessibilityValue(Text(selectedSpace?.name ?? "Space"))
        .accessibilityIdentifier("peek-space-picker")
        .help("Open in another Space")
    }
}

#if DEBUG
    #Preview("Component") {
        let spaces = SpaceModel.previewSpaces.map(\.identity)
        BrowserPeekDestinationMenu(spaces: spaces, selectedSpace: spaces[0], openInSpace: { _ in }).padding()
    }
#endif
