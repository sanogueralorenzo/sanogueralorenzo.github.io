import SwiftUI

struct BrowserRootSidebarLayoutReservation: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let isApproachingDock: Bool

    var body: some View {
        Color.clear
            .frame(
                width: presentation.reservedWidth(
                    for: width,
                    whileApproachingDock: isApproachingDock
                ),
                alignment: .leading
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
