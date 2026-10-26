import SwiftUI

/// The seam a lifted sidebar row will drop into.
struct BrowserSidebarReorderIndicatorLine: View {
    let indicator: BrowserSidebarReorderIndicator

    var body: some View {
        Capsule(style: .continuous)
            .fill(CrestColor.dropIndicator)
            .frame(
                width: indicator.flowsHorizontally
                    ? BrowserSidebarReorderIndicatorMetrics.thickness
                    : nil,
                height: indicator.flowsHorizontally
                    ? nil
                    : BrowserSidebarReorderIndicatorMetrics.thickness
            )
            .padding(
                indicator.flowsHorizontally ? .vertical : .horizontal,
                BrowserSidebarReorderIndicatorMetrics.inset
            )
            .offset(
                x: indicator.flowsHorizontally ? offset : 0,
                y: indicator.flowsHorizontally ? 0 : offset
            )
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    private var offset: CGFloat {
        let outset = BrowserSidebarReorderIndicatorMetrics.outset
        return indicator.side == .before ? -outset : outset
    }
}
