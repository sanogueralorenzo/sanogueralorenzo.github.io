import SwiftUI

/// The palette's query field and results on the palette's surface.
///
/// An overlay card given a namespace and a resting width grows out of its
/// Space's sidebar address field and shrinks back into it. Its surface takes
/// the field's frame and corner radius and animates to its own, while the
/// contents keep their resting layout and show through the growing frame from
/// the top, so no text is squeezed on the way. The field hands over the shared
/// identity as the card arrives (``BrowserCommandPaletteHandoff``); where no
/// field holds it, the card simply appears where it rests.
struct BrowserCommandPaletteCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.browserCommandPaletteTransitionPhase) private var transitionPhase

    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let maximumResultAreaHeight: CGFloat
    let morphNamespace: Namespace.ID?
    /// The width the card comes to rest at, which its contents keep while the
    /// card's frame morphs. Absent where the card never morphs.
    let restingWidth: CGFloat?
    let queryIsFocused: FocusState<Bool>.Binding

    /// Whether the card has arrived, rather than growing in or shrinking away.
    private var isSettled: Bool { transitionPhase.isIdentity }

    /// The identity the card shares with its Space's address field.
    private var morph: BrowserCommandSurfaceMorph? {
        model.space.map { .commandPalette(spaceID: $0.id) }
    }

    var body: some View {
        surface
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("command-palette")
    }

    @ViewBuilder
    private var surface: some View {
        if let morphNamespace, let morph, let restingWidth,
            BrowserCommandSurfaceMorph.animatesCommandPalette(reduceMotion: reduceMotion)
        {
            contents
                .frame(width: restingWidth)
                .animation(contentsAnimation) {
                    $0.opacity(isSettled ? 1 : 0)
                        .scaleEffect(
                            isSettled ? 1 : BrowserCommandPaletteMetrics.morphContentScale,
                            anchor: .top
                        )
                }
                // Takes whatever frame the morph proposes. The resting
                // contents overflow it from the top, where the query row is.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .modifier(
                    BrowserCommandPaletteShellMaterial(
                        shape: morphingShape,
                        reduceTransparency: reduceTransparency
                    )
                )
                .clipShape(morphingShape)
                .modifier(BrowserSearchProviderGlow(color: model.activeProvider?.color, shape: morphingShape))
                .animation(glassAnimation) {
                    $0.opacity(isSettled ? 1 : 0)
                }
                .matchedGeometryEffect(
                    id: morph,
                    in: morphNamespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: true
                )
                // At rest the card is exactly its contents' size; only the
                // morph proposes another.
                .fixedSize()
        } else {
            contents
                .frame(maxWidth: BrowserCommandPaletteMetrics.maximumCardWidth)
                .modifier(
                    BrowserCommandPaletteShellMaterial(
                        shape: restingShape,
                        reduceTransparency: reduceTransparency
                    )
                )
                .clipShape(restingShape)
                .modifier(BrowserSearchProviderGlow(color: model.activeProvider?.color, shape: restingShape))
                .opacity(isSettled ? 1 : 0)
        }
    }

    /// The field, the provider chips while what is typed names some, and the
    /// results. An overlay card keeps one height whatever the results, so it
    /// never moves as they change; the chips take their room from the results.
    private var contents: some View {
        VStack(spacing: 0) {
            BrowserCommandPaletteSearchField(
                model: model,
                presentation: presentation,
                queryIsFocused: queryIsFocused
            )

            if !model.providerChips.isEmpty {
                BrowserCommandPaletteProviderChips(model: model)
            }

            if keepsHeight || !model.groups.isEmpty {
                Divider()
                BrowserCommandPaletteResultList(
                    model: model,
                    maximumResultAreaHeight: resultAreaHeight,
                    fillsHeight: keepsHeight
                )
            }
        }
    }

    /// Whether the card keeps one height while its results change.
    private var keepsHeight: Bool { presentation == .overlay }

    /// The height the results may take, less what the provider chips take
    /// from a card that keeps its height.
    private var resultAreaHeight: CGFloat {
        guard keepsHeight, !model.providerChips.isEmpty else { return maximumResultAreaHeight }
        return max(0, maximumResultAreaHeight - BrowserCommandPaletteMetrics.providerChipRowHeight)
    }

    /// The card's own outline at rest, and the field's while the card is
    /// growing out of it or shrinking back, animated with the frame.
    private var morphingShape: RoundedRectangle {
        isSettled
            ? restingShape
            : RoundedRectangle(
                cornerRadius: BrowserDeviceAppearanceStore.shared.sidebarCornerRadius,
                style: .continuous
            )
    }

    private var restingShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: BrowserCommandPaletteMetrics.cardCornerRadius,
            style: .continuous
        )
    }

    /// The contents appear once the frame has nearly settled, and clear
    /// before it starts to shrink.
    private var contentsAnimation: Animation? {
        let fade = isSettled ? BrowserCommandSurfaceMorph.trailingFade : BrowserCommandSurfaceMorph.leadingFade
        return fade.unlessReducingMotion(reduceMotion)
    }

    /// The glass takes over from the field as the frame leaves it, and hands
    /// back to the field as the frame lands on it.
    private var glassAnimation: Animation? {
        let fade = isSettled ? BrowserCommandSurfaceMorph.leadingFade : BrowserCommandSurfaceMorph.trailingFade
        return fade.unlessReducingMotion(reduceMotion)
    }
}
