import SwiftUI

struct BrowserUtilityFanControl: View {
    let isExpanded: Bool
    let origin: CGPoint
    let destination: CGPoint
    let selectedSurface: BrowserUtilitySurface?
    let badgeColor: Color
    let downloads: [DownloadState]
    let newDownloadCount: Int
    let select: (BrowserUtilitySurface) -> Void
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var revealedSurfaces: Set<BrowserUtilitySurface> = []
    @State private var isContainerVisible = false

    var body: some View {
        ZStack {
            ForEach(
                BrowserUtilitySwitcherLayout.destinations.enumerated(),
                id: \.element
            ) { index, surface in
                let isRevealed = revealedSurfaces.contains(surface)
                let destinationPosition = CGPoint(
                    x: destination.x,
                    y: destination.y
                        + BrowserUtilitySwitcherLayout.verticalOffset(
                            for: index,
                            count: BrowserUtilitySwitcherLayout.destinations.count
                        )
                )
                BrowserUtilityFanDestinationButton(
                    surface: surface,
                    selectedSurface: selectedSurface,
                    badgeColor: badgeColor,
                    downloads: downloads,
                    newDownloadCount: newDownloadCount,
                    select: select
                )
                .scaleEffect(
                    isRevealed ? 1 : BrowserUtilitySwitcherLayout.collapsedScale
                )
                .opacity(isRevealed ? 1 : 0)
                // Each destination keeps its own glass surface. A shared
                // GlassEffectContainer morphs the three overlapping surfaces
                // independently from their labels while the fan is moving.
                .position(isRevealed ? destinationPosition : origin)
                .allowsHitTesting(isExpanded && isRevealed)
                .accessibilityHidden(!isExpanded || !isRevealed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isContainerVisible ? 1 : 0)
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .task(id: isExpanded) {
            await updatePresentation()
        }
    }

    @MainActor
    private func updatePresentation() async {
        let shouldReduceMotion = reduceMotionOverride ?? reduceMotion
        if shouldReduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                revealedSurfaces =
                    isExpanded
                    ? Set(BrowserUtilitySwitcherLayout.destinations)
                    : []
                isContainerVisible = isExpanded
            }
            return
        }

        if isExpanded {
            var initialTransaction = Transaction()
            initialTransaction.disablesAnimations = true
            withTransaction(initialTransaction) {
                revealedSurfaces.removeAll()
                isContainerVisible = true
            }
            for step in BrowserUtilitySwitcherLayout.expansionSteps {
                guard await step.run(on: self, reduceMotion: shouldReduceMotion) else { return }
            }
        } else {
            withAnimation(
                CrestMotion.dismissal.unlessReducingMotion(shouldReduceMotion)
            ) {
                revealedSurfaces.removeAll()
                isContainerVisible = false
            }
        }
    }

}
