import SwiftUI

/// One stable page tree and sidebar tree for either physical side, shared by
/// desktop windows and the expanded or floating mobile shell.
struct BrowserSidebarPageLayout<Detail: View, Sidebar: View, Controls: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let edge: HorizontalEdge
    var isApproachingDock = false
    @ViewBuilder let detail: Detail
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let controls: Controls

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                BrowserRootSidebarLayoutReservation(
                    presentation: presentation, width: edge == .leading ? width : 0,
                    isApproachingDock: isApproachingDock)
                detail.anchorPreference(key: BrowserRootPageBoundsKey.self, value: .bounds) { $0 }
                BrowserRootSidebarLayoutReservation(
                    presentation: presentation, width: edge == .trailing ? width : 0,
                    isApproachingDock: isApproachingDock)
            }
            sidebar.frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
            controls.frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
        }
    }
}

struct BrowserRootPageBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
