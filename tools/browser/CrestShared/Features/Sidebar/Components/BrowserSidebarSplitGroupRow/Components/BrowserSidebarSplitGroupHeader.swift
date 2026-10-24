import SwiftUI

/// The group's own identity and action strip.
///
/// It earns its place twice over now that members are ordinary tab rows. It is
/// the only thing that says "these rows are one split" before you notice the
/// container behind them — full-height rows otherwise read as neighbours that
/// happen to share a tint. And every member row carries a context menu of its
/// own, together covering all but a thin frame of the container, so without a
/// strip that belongs to the group there would be nowhere left to press for
/// "Separate All Tabs".
struct BrowserSidebarSplitGroupHeader: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    var body: some View {
        HStack(spacing: configuration.metrics.headerSpacing) {
            BrowserSidebarSplitGroupIcon(configuration: configuration)
                .browserIconCustomizationPopover(
                    BrowserIconCustomizationPresentation(
                        isPresented: interaction.isChoosingIcon,
                        title: "Split View Icon",
                        currentEmoji: configuration.emojiIcon,
                        showsReset: configuration.emojiIcon != nil,
                        resetTitle: "Use Stacked Icons",
                        setEmoji: interaction.setEmojiIcon,
                        reset: interaction.resetIcon
                    )
                )

            if interaction.isRenaming {
                TextField("Split View Name", text: interaction.draftTitle)
                    .textFieldStyle(.plain)
                    .focused(interaction.isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit(interaction.commitTitle)
                    .onKeyPress(.escape) {
                        interaction.cancelTitleEditing()
                        return .handled
                    }
                    .accessibilityIdentifier("split-group-rename-field")
            } else {
                Button(action: interaction.activate) {
                    Text(configuration.shownTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .modifier(
                    BrowserPlatformRowAuxiliaryClickModifier(
                        perform: configuration.canClose ? interaction.closeSplit : nil
                    )
                )
                .accessibilityLabel(configuration.shownTitle)
                .accessibilityValue(
                    "Split View with \(configuration.members.count) tabs"
                )
                .accessibilityAddTraits(
                    configuration.isPresented ? .isSelected : []
                )
            }

            Spacer(minLength: 0)

            Menu {
                BrowserSidebarSplitGroupContextMenu(
                    configuration: configuration,
                    interaction: interaction
                )
            } label: {
                Image(systemName: "ellipsis")
                    .frame(
                        width: configuration.metrics.headerHeight,
                        height: configuration.metrics.headerHeight
                    )
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .crestMenuActionLabelStyle()
            .tint(.primary)
            .accessibilityLabel("Split View actions")
            .disabled(!configuration.isAvailableForDisplay)
        }
        .frame(height: configuration.metrics.headerHeight)
        .padding(.horizontal, configuration.headerLeadingInset)
        .contentShape(.rect)
        .browserSplitGroupDraggable(
            item: configuration.dragItem,
            members: configuration.members,
            favicons: configuration.context.favicons,
            placement: configuration.placement,
            folderID: configuration.folderID,
            reorder: configuration.reorderContext,
            isEnabled: configuration.isAvailableForDisplay && configuration.capabilities.supportsOrganization
                && !interaction.isRenaming,
            requiresSelectedSpace: true
        )
        .contextMenu {
            if configuration.capabilities.supportsOrganization {
                BrowserSidebarSplitGroupContextMenu(configuration: configuration, interaction: interaction)
                    .tint(.primary)
                    .onAppear {
                        configuration.sidebarInteraction.sidebarReorderState.yieldToCompetingInteraction()
                    }
            }
        }
        .onChange(of: interaction.isTitleFocused.wrappedValue) { _, focused in
            if !focused, interaction.isRenaming {
                interaction.commitTitle()
            }
        }
    }
}

private struct BrowserSidebarSplitGroupIcon: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let emoji = configuration.emojiIcon {
                Text(emoji)
                    .font(.system(size: configuration.metrics.headerGlyphSize))
            } else {
                faviconStack
            }
        }
        .frame(
            width: configuration.metrics.headerGlyphSize * 1.45,
            height: configuration.metrics.headerGlyphSize
        )
        .accessibilityHidden(true)
    }

    private var faviconStack: some View {
        ZStack(alignment: .leading) {
            ForEach(
                Array(deckMembers.enumerated()),
                id: \.element.id
            ) { index, member in
                let isFocused = member.id == configuration.focusedMemberID
                let shouldAnimateLift = !reduceMotion

                TabStateFaviconView(
                    tab: member,
                    favicons: configuration.context.favicons,
                    profileID: configuration.profileID,
                    size: configuration.metrics.headerGlyphSize * 0.78
                )
                .padding(1)
                .background { CrestSurfaceLayer(shape: Circle()) }
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color.primary.opacity(CrestOpacity.border),
                            lineWidth: CrestLayout.hairline
                        )
                }
                .scaleEffect(deckScale(at: index))
                .rotationEffect(
                    .degrees(deckRotation(at: index)),
                    anchor: .bottom
                )
                .offset(
                    x: deckHorizontalOffset(at: index),
                    y: deckVerticalOffset(at: index)
                )
                .zIndex(Double(index))
                .transition(.scale(scale: 0.82).combined(with: .opacity))
                .animation(deckAnimation, value: configuration.focusedMemberID)
                .keyframeAnimator(
                    initialValue: CGFloat.zero,
                    trigger: configuration.focusedMemberID
                ) { content, lift in
                    content.offset(
                        y: isFocused && shouldAnimateLift ? lift : 0
                    )
                } keyframes: { _ in
                    CubicKeyframe(
                        -configuration.metrics.headerGlyphSize * 0.18,
                        duration: CrestMotion.collectionTransition / 2
                    )
                    CubicKeyframe(
                        0,
                        duration: CrestMotion.collectionTransition / 2
                    )
                }
            }
        }
    }

    private var deckMembers: [TabStateModel] {
        BrowserSidebarSplitGroupIconDeck.orderedMembers(
            configuration.members,
            focusedMemberID: configuration.focusedMemberID
        )
    }

    private var frontIndex: Int {
        max(deckMembers.count - 1, 0)
    }

    private func deckScale(at index: Int) -> CGFloat {
        1 - CGFloat(frontIndex - index) * 0.055
    }

    private func deckRotation(at index: Int) -> Double {
        Double(index - frontIndex) * 3.5
    }

    private func deckHorizontalOffset(at index: Int) -> CGFloat {
        CGFloat(index) * configuration.metrics.headerGlyphSize * 0.28
    }

    private func deckVerticalOffset(at index: Int) -> CGFloat {
        CGFloat(frontIndex - index) * configuration.metrics.headerGlyphSize * 0.045
    }

    private var deckAnimation: Animation? {
        CrestMotion.collection.unlessReducingMotion(reduceMotion)
    }
}

/// A split may contain more members than the compact header can draw. The
/// focused member is always admitted to the visible deck and placed last so it
/// renders above the other cards; stable tab identity then lets SwiftUI move
/// each favicon through the deck instead of replacing the whole stack.
enum BrowserSidebarSplitGroupIconDeck {
    static let visibleLimit = 3

    static func orderedMembers<Member: Identifiable>(
        _ members: [Member],
        focusedMemberID: UUID?,
        limit: Int = visibleLimit
    ) -> [Member] where Member.ID == UUID {
        guard limit > 0 else { return [] }

        var visible = Array(members.prefix(limit))
        guard let focused = members.first(where: { $0.id == focusedMemberID })
        else { return visible }

        if !visible.contains(where: { $0.id == focused.id }) {
            if visible.isEmpty {
                visible.append(focused)
            } else {
                visible[visible.index(before: visible.endIndex)] = focused
            }
        }

        visible.removeAll { $0.id == focused.id }
        visible.append(focused)
        return visible
    }
}
