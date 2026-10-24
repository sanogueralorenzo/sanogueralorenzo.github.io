import SwiftUI

/// Shared icon buttons, selection, and reordering for desktop and touch Space
/// pickers, over Spaces of the read model's identities or draft values.
struct CrestSpaceIconPicker<Space: BrowserSpaceIdentifying, SegmentContent: View>: View {
    // MARK: - Variables

    let spaces: [Space]
    let selectedSpaceID: UUID?
    let selectSpace: (UUID) -> Void
    var style: CrestSpaceIconPickerStyle = .compact
    var selectionTint: Color? = nil
    var accessibilityIdentifier: String?
    var moveSpace: ((UUID, UUID) -> Void)? = nil
    var reorderViewport = CGRect.zero
    var selectionPresentation: SpacePagerPresentation? = nil
    var segmentSize = CGSize(
        width: CrestSpaceIconPickerMetrics.segmentWidth,
        height: CrestSpaceIconPickerMetrics.segmentHeight)
    @ViewBuilder let segmentContent: (Space) -> SegmentContent

    @State private var reorder = CrestSpacePickerReordering()
    @State private var frames: [UUID: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        HStack(spacing: 0) {
            ForEach(spaces) { space in
                reorderableButton(space)
                    .zIndex(reorder.sourceID == space.id ? 1 : 0)
            }
        }
        .padding(style.trackPadding)
        .backgroundPreferenceValue(CrestSpaceIconFramePreference.self) { anchors in
            if let selectionPresentation {
                GeometryReader { geometry in
                    PlatformSpacePickerPresentation(
                        presentation: selectionPresentation,
                        style: style,
                        spaces: spaces.map(\.identity),
                        selectedSpaceID: selectedSpaceID,
                        frames: anchors.mapValues { geometry[$0] },
                        selectionTint: selectionTint
                    )
                }
            }
        }
        .background {
            CrestSpaceIconPickerShape(style: style)
                .fill(.primary.opacity(style.trackFillOpacity))
        }
        .overlay {
            CrestSpaceIconPickerShape(style: style)
                .strokeBorder(
                    .primary.opacity(style.trackBorderOpacity),
                    lineWidth: CrestLayout.hairline / 2
                )
        }
        .fixedSize(horizontal: true, vertical: false)
        .background {
            #if os(macOS)
                if moveSpace != nil {
                    BrowserSpacePickerAutoscroll(
                        viewport: reorderViewport,
                        pointer: reorder.sourceID == nil ? nil : reorder.pointer
                    ) { offset in
                        guard reorder.sourceID != nil else { return }
                        frames = frames.mapValues { $0.offsetBy(dx: offset, dy: 0) }
                        reorder.contentMoved(by: offset, ids: spaces.map(\.id), frames: frames)
                    }
                }
            #endif
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: spaces.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space")
        .crestAccessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder private func reorderableButton(_ space: Space) -> some View {
        if let moveSpace {
            let lifted = reorder.sourceID == space.id
            spaceButton(space)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    guard reorder.sourceID == nil else { return }
                    frames[space.id] = $0
                }
                .offset(reorder.offset(for: space.id, ids: spaces.map(\.id), frames: frames))
                .scaleEffect(lifted ? 1.08 : 1)
                .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 4, y: 2)
                .animation(
                    reduceMotion || lifted ? nil : CrestMotion.dragSource,
                    value: reorder.targetID
                )
                .modifier(
                    BrowserPlatformSidebarReorderLiftGesture { start, pointer in
                        reorder.update(
                            source: space.id, ids: spaces.map(\.id), frames: frames, start: start, pointer: pointer,
                            viewport: reorderViewport)
                    } released: {
                        guard reorder.sourceID == space.id else { return }
                        if let move = reorder.end() { moveSpace(move.source, move.target) }
                    }
                )
                #if os(macOS)
                    .accessibilityHint("Select this Space, or drag to reorder")
                #else
                    .accessibilityHint("Touch and hold for options to reorder Spaces")
                #endif
                .contextMenu {
                    if let index = spaces.firstIndex(where: { $0.id == space.id }) {
                        Button("Move Left", systemImage: "arrow.left") {
                            moveSpace(space.id, spaces[index - 1].id)
                        }
                        .disabled(index == 0)
                        Button("Move Right", systemImage: "arrow.right") {
                            moveSpace(space.id, spaces[index + 1].id)
                        }
                        .disabled(index == spaces.count - 1)
                    }
                }
        } else {
            spaceButton(space)
        }
    }

    private func spaceButton(_ space: Space) -> some View {
        let identity = space.identity
        let isSelected = space.id == selectedSpaceID
        let tint = selectionTint ?? identity.branding.primaryColor.color
        let accessibilityValue = accessibilityValue(
            isSelected: isSelected,
            requiresAuthentication: identity.requiresAuthentication
        )

        return Button {
            selectSpace(space.id)
        } label: {
            segmentContent(space)
                .frame(
                    width: segmentSize.width,
                    height: segmentSize.height
                )
                .contentShape(.rect)
                .background {
                    if isSelected && selectionPresentation == nil {
                        CrestSpaceIconPickerShape(style: style)
                            .fill((style.tintsSelection ? tint : Color.primary).opacity(style.selectionFillOpacity))
                            .overlay {
                                CrestSpaceIconPickerShape(style: style)
                                    .strokeBorder(style.tintsSelection ? tint : .clear, lineWidth: CrestLayout.hairline)
                            }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: identity.name))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(identity.name)
        .id(space.id)
        .anchorPreference(key: CrestSpaceIconFramePreference.self, value: .bounds) { anchor in
            selectionPresentation == nil ? [:] : [space.id: anchor]
        }
    }

    private func accessibilityValue(
        isSelected: Bool,
        requiresAuthentication: Bool
    ) -> LocalizedStringResource {
        switch (isSelected, requiresAuthentication) {
        case (true, true):
            "Selected, Private Space"
        case (true, false):
            "Selected, Open Space"
        case (false, true):
            "Private Space"
        case (false, false):
            "Open Space"
        }
    }
}

/// These anchors change with icon layout, not with native scroll or page motion.
private struct CrestSpaceIconFramePreference: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [UUID: Anchor<CGRect>],
        nextValue: () -> [UUID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
