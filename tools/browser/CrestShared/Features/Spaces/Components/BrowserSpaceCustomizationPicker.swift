import SwiftUI

/// Uses the live sidebar's track, artwork, and overflow controls. The host owns
/// selection and ordering, whether it is editing the read model's Spaces or a
/// setup draft.
struct BrowserSpaceCustomizationPicker: View {
    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let selectSpace: (UUID) -> Void
    let moveSpace: (UUID, UUID) -> Void
    let addSpace: () -> Void

    private var usesTouch: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    // MARK: - Initializers

    init(
        spaces: [some BrowserSpaceIdentifying],
        selectedSpaceID: UUID,
        selectSpace: @escaping (UUID) -> Void,
        moveSpace: @escaping (UUID, UUID) -> Void,
        addSpace: @escaping () -> Void
    ) {
        self.spaces = spaces.map(\.identity)
        self.selectedSpaceID = selectedSpaceID
        self.selectSpace = selectSpace
        self.moveSpace = moveSpace
        self.addSpace = addSpace
    }

    // MARK: - Body

    var body: some View {
        #if os(iOS)
            HStack(spacing: 8) {
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        CrestSpaceIconPicker(
                            spaces: spaces, selectedSpaceID: selectedSpaceID, selectSpace: selectSpace,
                            moveSpace: moveSpace, segmentSize: CGSize(width: 44, height: 44)
                        ) { space in
                            BrowserSpacePickerIcon(space: space, metrics: .touch)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selectedSpaceID) { _, id in
                        reader.scrollTo(id, anchor: .center)
                    }
                }
                Button("New Space", systemImage: "plus", action: addSpace)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("space-customization-add")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(height: 62)
        #else
            HStack(spacing: 0) {
                GeometryReader { geometry in
                    // Only the picker occupies this lane; the plus has its own width
                    // so it does not reserve a matching empty utility on the left.
                    let allocation = BrowserSpaceSwitcherLayout.compactStripAllocation(
                        availableWidth: geometry.size.width, spaceCount: spaces.count,
                        leadingUtilityWidth: 0, trailingUtilityWidth: 0)
                    BrowserSpaceSwitcherCompactPicker(
                        spaces: spaces, selectedSpaceID: selectedSpaceID,
                        metrics: usesTouch ? .touch : .pointer, selectSpace: selectSpace, allocation: allocation,
                        moveSpace: moveSpace
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button("New Space", systemImage: "plus", action: addSpace)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: usesTouch ? 44 : 24, height: usesTouch ? 44 : 24)
                    .help("New Space")
                    .accessibilityIdentifier("space-customization-add")
            }
            .padding(.trailing, BrowserSpaceSwitcherLayout.compactStripHorizontalInset)
            .frame(height: BrowserSpaceSwitcherLayout.compactStripHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Spaces")
        #endif
    }
}
