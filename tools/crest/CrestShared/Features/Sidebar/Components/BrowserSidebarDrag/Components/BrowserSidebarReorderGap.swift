import SwiftUI

/// The single vacant slot under a lifted item. Its real height participates in
/// layout, so surrounding rows and folder surfaces settle around the drop.
struct BrowserSidebarReorderGap: View {
    let height: CGFloat

    /// The slot takes the shape of a layer where it stands.
    @Environment(\.sidebarLayerDepth) private var depth

    var body: some View {
        RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth), style: .continuous)
            .fill(.primary.opacity(0.035))
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.vertical, CrestSpacing.extraSmall)
            .frame(height: height)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
