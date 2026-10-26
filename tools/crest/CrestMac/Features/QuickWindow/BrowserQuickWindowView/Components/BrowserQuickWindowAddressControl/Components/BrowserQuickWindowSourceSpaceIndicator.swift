import SwiftUI

/// The Space the Quick Window browses, which opens the Spaces it may switch
/// to: choosing one reopens the page with that Space's website data and
/// passwords.
struct BrowserQuickWindowSourceSpaceIndicator: View {
    let space: BrowserSpaceIdentity?
    let spaces: [BrowserSpaceIdentity]
    let selectSpace: (BrowserSpaceRuntimeAssignment) -> Void

    @State private var isPickerPresented = false

    var body: some View {
        Button {
            isPickerPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                if let space {
                    BrowserSpaceSymbolArtwork(space: space, size: 20, lockSize: 5)
                } else {
                    Image(systemName: "square.grid.2x2")
                }
                Text(space?.name ?? "Space")
                    .lineLimit(1)
            }
            .font(.callout.weight(.semibold))
            .padding(
                .horizontal,
                BrowserQuickWindowLayout.sourceChipHorizontalPadding
            )
            .frame(height: CrestLayout.minimumHitTarget)
            .background(
                CrestColor.hover,
                in: .rect(cornerRadius: CrestRadius.compact, style: .continuous)
            )
        }
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact)
        )
        .disabled(space == nil)
        .fixedSize()
        .accessibilityLabel("Current Quick Window Space")
        .accessibilityValue(space?.name ?? "Space")
        .accessibilityIdentifier("quick-window-source-space")
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            if let space {
                BrowserQuickWindowSpacePicker(
                    spaces: spaces,
                    selectedSpaceID: space.id,
                    purpose: .browsingSpace
                ) { candidate in
                    isPickerPresented = false
                    selectSpace(candidate.assignment)
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        let spaces = SpaceModel.previewSpaces.map(\.identity)
        BrowserQuickWindowSourceSpaceIndicator(space: spaces[0], spaces: spaces, selectSpace: { _ in })
            .padding()
    }
#endif
