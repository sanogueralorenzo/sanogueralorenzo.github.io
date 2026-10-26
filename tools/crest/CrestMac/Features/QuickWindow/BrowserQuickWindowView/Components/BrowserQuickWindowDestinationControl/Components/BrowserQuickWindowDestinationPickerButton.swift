import SwiftUI

struct BrowserQuickWindowDestinationPickerButton: View {
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    @Binding var isPresented: Bool
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: CGSize(
                    width: BrowserQuickWindowLayout.minimumMacHitTarget,
                    height: BrowserQuickWindowLayout.controlHeight
                ),
                cornerRadius: CrestRadius.compact
            )
        )
        .accessibilityLabel("Choose Destination Space")
        .accessibilityIdentifier("quick-window-destination-space-picker")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            BrowserQuickWindowSpacePicker(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID
            ) { candidate in
                isPresented = false
                promote(candidate.assignment)
            }
        }
    }
}

#if DEBUG
    #Preview("Destination picker") {
        @Previewable @State var presented = false
        let spaces = SpaceModel.previewSpaces.map(\.identity)
        BrowserQuickWindowDestinationPickerButton(
            spaces: spaces, selectedSpaceID: spaces[0].id, isPresented: $presented, promote: { _ in }
        ).padding()
    }
#endif
