import SwiftUI

struct BrowserQuickWindowSpacePicker: View {
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let selectSpace: (BrowserSpaceIdentity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spaces")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)
            ForEach(spaces) { space in
                BrowserQuickWindowSpacePickerRow(
                    space: space,
                    isSelected: space.id == selectedSpaceID,
                    select: { selectSpace(space) }
                )
            }
        }
        .padding(6)
        .frame(width: BrowserQuickWindowLayout.spacePickerWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose Destination Space")
    }
}
