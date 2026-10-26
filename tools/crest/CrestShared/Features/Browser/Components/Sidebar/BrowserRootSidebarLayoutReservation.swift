import SwiftUI

struct BrowserRootSidebarLayoutReservation: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat

    var body: some View {
        Color.clear
            .frame(
                width: presentation.reservedWidth(
                    for: width
                ),
                alignment: .leading
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
