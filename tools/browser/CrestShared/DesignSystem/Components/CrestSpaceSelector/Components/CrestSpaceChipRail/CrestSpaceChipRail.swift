import SwiftUI

/// A horizontal rail of crest-badged Space chips, ending in a dashed add chip.
struct CrestSpaceChipRail: View {
    let spaces: [CrestSpaceIdentity]
    @Binding var selection: UUID?
    var add: CrestSpaceChipAddAction?
    var commands: ((CrestSpaceIdentity) -> [CrestSpaceChipCommand])?
    var accessibilityIdentifier: String?

    init(
        spaces: [CrestSpaceIdentity],
        selection: Binding<UUID?>,
        add: CrestSpaceChipAddAction? = nil,
        commands: ((CrestSpaceIdentity) -> [CrestSpaceChipCommand])? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.spaces = spaces
        _selection = selection
        self.add = add
        self.commands = commands
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CrestSpaceChipMetrics.railSpacing) {
                ForEach(spaces) { identity in
                    chip(identity)
                }

                if let add {
                    addChip(add)
                }
            }
            .padding(.vertical, CrestSpacing.extraExtraSmall)
            .crestCollectionMotion(ids: spaces.map(\.id))
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .crestAccessibilityIdentifier(accessibilityIdentifier)
    }

    private func chip(_ identity: CrestSpaceIdentity) -> some View {
        let isSelected = identity.id == selection
        return Button {
            selection = identity.id
        } label: {
            HStack(spacing: CrestSpaceChipMetrics.contentSpacing) {
                BrowserSpaceSymbolArtwork(
                    identity: identity.space,
                    size: CrestSpaceChipMetrics.iconSize,
                    lockSize: CrestSpaceChipMetrics.lockSize
                )
                Text(verbatim: identity.name)
                    .lineLimit(1)
            }
        }
        .buttonStyle(
            CrestSpaceChipStyle(tint: identity.tint, isSelected: isSelected)
        )
        .accessibilityLabel(Text(verbatim: identity.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .crestCollectionItemTransition()
        .modifier(CrestSpaceChipCommands(commands: commands?(identity) ?? []))
    }

    private func addChip(_ add: CrestSpaceChipAddAction) -> some View {
        Button(action: add.perform) {
            HStack(spacing: CrestSpaceChipMetrics.contentSpacing) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                Text(add.title)
                    .lineLimit(1)
            }
        }
        .buttonStyle(CrestSpaceAddChipStyle(tint: addTint))
        .accessibilityLabel(Text(add.title))
        .crestAccessibilityIdentifier(add.accessibilityIdentifier)
    }

    private var addTint: Color {
        spaces.first { $0.id == selection }?.tint ?? CrestBrandTheme.accent
    }
}

#if DEBUG
    #Preview("Select a Space") {
        @Previewable @State var selection: UUID? = SessionState.Seed.preview.spaces[0].id
        CrestSpaceChipRail(spaces: CrestSpaceIdentity.list(SpaceModel.previewSpaces), selection: $selection)
            .padding().frame(width: 360)
    }
#endif
