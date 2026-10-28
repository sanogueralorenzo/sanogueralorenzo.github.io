import SwiftUI

extension View {
    /// Lets a section's run draw its own insertion line while it holds no rows.
    func browserSidebarReorderSectionIndicator(
        _ section: BrowserSidebarReorderSection,
        state: BrowserSidebarReorderState
    ) -> some View {
        modifier(
            BrowserSidebarReorderSectionIndicatorModifier(
                section: section,
                state: state
            )
        )
    }

    /// Expands a vertical destination run by the incoming row's measured
    /// height, complementing the presentation offsets that open its gap.
    func browserSidebarReorderSectionReservation(
        _ section: BrowserSidebarReorderSection,
        state: BrowserSidebarReorderState
    ) -> some View {
        modifier(
            BrowserSidebarReorderSectionReservationModifier(
                section: section,
                state: state
            )
        )
    }
}
