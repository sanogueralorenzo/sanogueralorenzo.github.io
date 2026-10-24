import SwiftUI

struct CrestFieldSurface: ViewModifier {
    /// Callers may also attach a programmatic focus binding; SwiftUI keeps both
    /// bindings synchronized against the same native field.
    @FocusState private var isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: CrestFieldMetrics.cornerRadius,
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .padding(.horizontal, CrestFieldMetrics.horizontalPadding)
            .frame(minHeight: CrestFieldMetrics.height)
            .background(CrestBrandTheme.canvas, in: shape)
            .overlay {
                shape.strokeBorder(
                    CrestBrandTheme.line,
                    lineWidth: CrestFieldMetrics.borderWidth
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: CrestFieldMetrics.cornerRadius
                        + CrestFieldMetrics.focusRingWidth / 2,
                    style: .continuous
                )
                .strokeBorder(
                    CrestBrandTheme.accent.opacity(CrestFieldMetrics.focusRingOpacity),
                    lineWidth: CrestFieldMetrics.focusRingWidth
                )
                .padding(-CrestFieldMetrics.focusRingWidth / 2)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
            }
            .animation(
                CrestMotion.press.unlessReducingMotion(reduceMotion),
                value: isFocused
            )
    }
}
