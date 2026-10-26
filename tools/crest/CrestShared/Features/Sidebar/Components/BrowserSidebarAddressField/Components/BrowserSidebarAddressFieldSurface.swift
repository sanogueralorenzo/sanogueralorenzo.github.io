import SwiftUI

struct BrowserSidebarAddressFieldSurface: ViewModifier {
    var metrics = BrowserSidebarAddressFieldMetrics.pointer
    var leadingPadding: CGFloat? = nil
    let progress: Double
    let isLoading: Bool
    let isEditing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        band(
            content
                .padding(.leading, leadingPadding ?? metrics.horizontalPadding)
                .padding(.trailing, metrics.horizontalPadding)
        )
        .background {
            ZStack(alignment: .leading) {
                CrestSurfaceLayer(
                    shape: fieldShape,
                    tint: CrestColor.chromeSurface,
                    hoverTint: isHovering ? CrestColor.hover : nil
                )
                fieldShape
                    .fill(accent.opacity(isLoading ? 0.2 : 0))
                    .scaleEffect(x: loadingProgress, anchor: .leading)
                    .mask(fieldShape)
                    .animation(
                        CrestMotion.loadingProgress.unlessReducingMotion(reduceMotion),
                        value: loadingProgress
                    )
            }
        }
        .overlay {
            fieldShape
                .strokeBorder(
                    isEditing ? metrics.editingRingColor : .clear,
                    lineWidth: metrics.editingRingWidth,
                    antialiased: true
                )
        }
        .onHover { isHovering = $0 }
        .animation(CrestMotion.surface.unlessReducingMotion(reduceMotion), value: isHovering)
    }

    @ViewBuilder
    private func band(_ content: some View) -> some View {
        if metrics.growsWithContent {
            content.frame(minHeight: metrics.height)
        } else {
            content.frame(height: metrics.height)
        }
    }

    private var loadingProgress: CGFloat {
        BrowserPageSurfacePresentation.loadingProgress(
            estimatedProgress: progress,
            isNavigating: isLoading
        )
    }

    private var accent: Color { CrestBrandTheme.accent }

    private var fieldShape: Capsule { Capsule() }
}

extension View {
    func browserAddressFieldSurface(
        metrics: BrowserSidebarAddressFieldMetrics = .pointer,
        leadingPadding: CGFloat? = nil,
        progress: Double,
        isLoading: Bool,
        isEditing: Bool
    ) -> some View {
        modifier(
            BrowserSidebarAddressFieldSurface(
                metrics: metrics,
                leadingPadding: leadingPadding,
                progress: progress,
                isLoading: isLoading,
                isEditing: isEditing
            )
        )
    }
}
