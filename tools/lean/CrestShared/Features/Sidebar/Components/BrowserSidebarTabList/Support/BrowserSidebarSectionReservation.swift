import SwiftUI

/// The layout capacity a section keeps for a row arriving from another section.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell that
/// reserves those places gives the destination run real room for the incoming
/// row instead of letting its offset neighbours paint over the section below.
/// Where the seam is aimable the reservation would only add an empty band
/// nothing lands in.
struct BrowserSidebarSectionReservation: ViewModifier {
    let section: BrowserSidebarReorderSection
    let state: BrowserSidebarReorderState
    let capabilities: BrowserInteractionCapabilities

    @ViewBuilder
    func body(content: Content) -> some View {
        if capabilities.reservesReorderSectionZones {
            content.browserSidebarReorderSectionReservation(
                section,
                state: state
            )
        } else {
            content
        }
    }
}
