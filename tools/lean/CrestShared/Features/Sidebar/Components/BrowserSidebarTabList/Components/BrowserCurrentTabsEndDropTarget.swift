import SwiftUI

/// The landing band the current run keeps at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell that
/// draws its drop feedback on the rows themselves keeps a band of its own after
/// the last one. It is also the band a cleared list draws its insertion line
/// in: with no rows left it sits directly above New Tab, where the
/// first current tab would appear.
struct BrowserCurrentTabsEndDropTarget: View {
    let context: BrowserSidebarListContext

    var body: some View {
        Color.clear
            .frame(height: context.capabilities.tabListMetrics.sectionEndBandHeight)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }
}
