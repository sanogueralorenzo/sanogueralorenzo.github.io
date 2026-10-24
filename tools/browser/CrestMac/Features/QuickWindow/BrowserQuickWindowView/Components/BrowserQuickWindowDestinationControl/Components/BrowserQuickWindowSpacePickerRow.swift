import SwiftUI

struct BrowserQuickWindowSpacePickerRow: View {
    let space: BrowserSpaceIdentity
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                BrowserSpaceSymbolArtwork(space: space, size: 22, lockSize: 5.5)
                Text(space.name).lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: BrowserQuickWindowLayout.spacePickerRowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .crestInteractiveSurface(
            isSelected: isSelected,
            isHovering: isHovering,
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
        .onHover { isHovering = $0 }
        .accessibilityLabel(space.name)
        .accessibilityValue(
            isSelected ? "Current destination" : "Available destination"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
    #Preview("Destination selection") {
        VStack(spacing: 8) {
            BrowserQuickWindowSpacePickerRow(
                space: BrowserSpaceBrandingPreviewFixture.simpleSpace.identity, isSelected: true, select: {})
            BrowserQuickWindowSpacePickerRow(
                space: BrowserSpaceBrandingPreviewFixture.crestSpace.identity, isSelected: false, select: {})
        }.padding().frame(width: 320)
    }
#endif
