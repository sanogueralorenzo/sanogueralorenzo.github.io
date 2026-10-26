import SwiftUI

struct BrowserQuickWindowSpacePicker: View {
    // MARK: - Types

    /// What choosing a Space does, as the picker and its rows announce it:
    /// the Space the page opens in, or the Space the Quick Window browses.
    struct Purpose {
        static let destination = Purpose(
            label: "Choose Destination Space",
            selectedValue: "Current destination",
            availableValue: "Available destination"
        )
        static let browsingSpace = Purpose(
            label: "Choose Quick Window Space",
            selectedValue: "Current Space",
            availableValue: "Available Space"
        )

        let label: LocalizedStringResource
        let selectedValue: LocalizedStringResource
        let availableValue: LocalizedStringResource
    }

    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    var purpose = Purpose.destination
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
                    purpose: purpose,
                    select: { selectSpace(space) }
                )
            }
        }
        .padding(6)
        .frame(width: BrowserQuickWindowLayout.spacePickerWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(purpose.label))
    }
}
