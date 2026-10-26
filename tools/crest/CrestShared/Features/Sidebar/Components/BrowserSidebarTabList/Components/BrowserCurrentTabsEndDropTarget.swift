import SwiftUI

/// The landing band the current run keeps at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell that
/// reserves section zones for imprecise input keeps a band of its own after the
/// last one. It is also the band a cleared list's section indicator stands in:
/// with no rows left it sits directly below the new-tab row, where the first
/// current tab would appear.
struct BrowserCurrentTabsEndDropTarget: View {
    let context: BrowserSidebarListContext

    var body: some View {
        Color.clear
            .frame(height: context.capabilities.tabListMetrics.sectionEndBandHeight)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }
}
