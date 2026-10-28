import SwiftUI

/// The stable root-level frame around browser content. Page states only choose
/// whether their interior is opaque; clipping, the theme seam, and elevation
/// remain owned here.
struct BrowserRootContentSurface<Content: View>: View {
    private static var boundaryStrokeWidth: CGFloat { 0.5 }
    private static var boundaryStrokeOpacity: Double { CrestOpacity.border }

    let cornerRadius: CGFloat
    let seamWidth: CGFloat
    let frameInsets: EdgeInsets
    let usesTransparentInnerSurface: Bool
    let showsFallbackBorder: Bool
    let showsBoundary: Bool
    let content: Content

    init(
        cornerRadius: CGFloat,
        seamWidth: CGFloat,
        frameInsets: EdgeInsets,
        usesTransparentInnerSurface: Bool,
        showsFallbackBorder: Bool = false,
        showsBoundary: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.seamWidth = seamWidth
        self.frameInsets = frameInsets
        self.usesTransparentInnerSurface = usesTransparentInnerSurface
        self.showsFallbackBorder = showsFallbackBorder
        self.showsBoundary = showsBoundary
        self.content = content()
    }

    var body: some View {
        let outerShape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        content
            .background {
                if usesTransparentInnerSurface {
                    Color.clear
                } else {
                    Rectangle().fill(.background)
                }
            }
            // Clip the assembled surface once. Independently clipped backing
            // layers otherwise leave a pale fringe along the upper corners.
            .compositingGroup()
            .clipShape(
                .rect(
                    cornerRadius: max(0, cornerRadius - seamWidth),
                    style: .continuous
                )
            )
            .padding(seamWidth)
            .clipShape(outerShape, style: FillStyle(antialiased: true))
            .background {
                CrestLiftedSurfaceShadow(
                    cornerRadius: cornerRadius,
                    opacity: showsBoundary
                        ? CrestLiftedSurfaceShadow.pageShadowOpacity
                        : 0,
                    radius: CrestLiftedSurfaceShadow.pageShadowRadius,
                    yOffset: CrestLiftedSurfaceShadow.pageShadowYOffset
                )
            }
            .overlay {
                outerShape
                    .strokeBorder(
                        Color.black.opacity(
                            showsBoundary
                                ? showsFallbackBorder
                                    ? CrestOpacity.border
                                    : Self.boundaryStrokeOpacity
                                : 0
                        ),
                        lineWidth: Self.boundaryStrokeWidth,
                        antialiased: true
                    )
                    .allowsHitTesting(false)
            }
            .padding(frameInsets)
    }
}
