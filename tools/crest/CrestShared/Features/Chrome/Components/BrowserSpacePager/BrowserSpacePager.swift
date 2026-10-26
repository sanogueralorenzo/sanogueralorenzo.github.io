import SwiftUI

/// Shared selection and accessibility contract; each input platform owns the
/// viewport motion without publishing a browsing-state change for every frame.
struct BrowserSpacePager<Content: View>: View {
    let spaces: [SpaceModel]
    let selectedSpaceID: UUID
    var isInteractionLocked = false
    /// The last Next or Previous Space step, which slides around the ends.
    var spaceStep: BrowserSpaceStep?
    /// Returns the actual selection so a refused request cannot leave native
    /// presentation waiting for a state change that will never arrive.
    let selectSpace: (UUID) -> UUID
    @ViewBuilder let content: (SpaceModel, Bool) -> Content

    var body: some View {
        platformPager
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Spaces")
            .accessibilityValue(
                BrowserChromeAccessibility.spaceValue(spaces: spaces, selectedSpaceID: selectedSpaceID)
            )
            .accessibilityIdentifier("space-pager")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: selectAdjacentSpace(.next)
                case .decrement: selectAdjacentSpace(.previous)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Previous Space") { selectAdjacentSpace(.previous) }
            .accessibilityAction(named: "Next Space") { selectAdjacentSpace(.next) }
    }

    private var platformPager: PlatformSpacePager<Content> {
        #if os(macOS)
            PlatformSpacePager(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                isInteractionLocked: isInteractionLocked,
                spaceStep: spaceStep,
                selectSpace: selectSpace,
                content: content
            )
        #else
            PlatformSpacePager(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                isInteractionLocked: isInteractionLocked,
                selectSpace: selectSpace,
                content: content
            )
        #endif
    }

    private func selectAdjacentSpace(_ direction: BrowserSpaceSwipeDirection) {
        guard !isInteractionLocked,
            let spaceID = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces, selectedSpaceID: selectedSpaceID,
                direction: direction == .next ? .next : .previous)
        else { return }
        _ = selectSpace(spaceID)
    }
}
