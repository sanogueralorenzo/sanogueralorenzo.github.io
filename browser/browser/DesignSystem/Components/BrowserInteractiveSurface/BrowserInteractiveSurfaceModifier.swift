import SwiftUI

enum BrowserInteractiveSurfaceMetrics {
    static let defaultSelectedBorderWidth: CGFloat = 0.5
    static let increasedContrastBorderWidth: CGFloat = 1.5
    static let selectedShadowRadius: CGFloat = 2
    static let selectedShadowYOffset: CGFloat = 1
}

struct BrowserInteractiveSurfaceModifier: ViewModifier {
    let isSelected: Bool
    var selectionEmphasis = false
    let isHovering: Bool
    let cornerRadius: CGFloat
    var cornerStyle: RoundedCornerStyle = .continuous
    let isPressed: Bool
    let showsRestingSurface: Bool
    let selectedBorderColor: Color
    let selectedBorderWidth: CGFloat
    var customHoverFill: Color? = nil
    var customSelectedFill: Color? = nil
    var customRestingFill: Color? = nil
    var restingBorderColor: Color = .clear

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: cornerStyle
        )
        let isEmphasized = isSelected || isPressed

        content
            .background {
                surface(in: shape)
                    .overlay { if selectionEmphasis { shape.fill(BrowserColor.hover) } }
            }
            .overlay {
                shape
                    .strokeBorder(
                        isEmphasized ? selectedBorderColor : restingBorderColor,
                        lineWidth: borderWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: isEmphasized
                    ? BrowserInteractiveSurfaceMetrics.selectedShadowRadius
                    : 0,
                y: isEmphasized
                    ? BrowserInteractiveSurfaceMetrics.selectedShadowYOffset
                    : 0
            )
            .animation(accessibleSurfaceAnimation, value: isHovering)
            .animation(accessibleSurfaceAnimation, value: selectionEmphasis)
            // Fading selection redraws both surfaces and their shadows on every tab switch.
            .animation(accessibleSurfaceAnimation, value: isPressed)
    }

    @ViewBuilder
    private func surface(in shape: RoundedRectangle) -> some View {
        if isSelected || isPressed || showsRestingSurface {
            BrowserSurfaceLayer(
                shape: shape,
                tint: isSelected || isPressed ? customSelectedFill : customRestingFill,
                hoverTint: isHovering ? hoverFill : nil
            )
        } else if isHovering {
            shape.fill(hoverFill)
        }
    }

    private var hoverFill: Color { customHoverFill ?? BrowserColor.hover }

    private var borderWidth: CGFloat {
        guard contrast == .increased else { return selectedBorderWidth }
        return max(
            BrowserInteractiveSurfaceMetrics.increasedContrastBorderWidth,
            selectedBorderWidth
        )
    }

    private var shadowOpacity: Double {
        guard isSelected || isPressed, !reduceTransparency else { return 0 }
        return BrowserOpacity.interactionSelectionShadow
    }

    private var accessibleSurfaceAnimation: Animation? {
        BrowserMotion.surface.unlessReducingMotion(reduceMotion)
    }
}

private struct BrowserHoverSurfaceModifier: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let cornerStyle: RoundedCornerStyle
    let isPressed: Bool
    let showsRestingSurface: Bool
    let selectedBorderColor: Color
    let selectedBorderWidth: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .browserInteractiveSurface(
                isSelected: isSelected,
                isHovering: isHovering && isEnabled,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle,
                isPressed: isPressed && isEnabled,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
            .onHover { isHovering = $0 }
    }
}

extension View {
    func browserInteractiveSurface(
        isSelected: Bool,
        isHovering: Bool,
        cornerRadius: CGFloat = BrowserRadius.compact,
        cornerStyle: RoundedCornerStyle = .continuous,
        selectionEmphasis: Bool = false,
        isPressed: Bool = false,
        showsRestingSurface: Bool = false,
        selectedBorderColor: Color = BrowserColor.selectedBorder,
        selectedBorderWidth: CGFloat =
            BrowserInteractiveSurfaceMetrics.defaultSelectedBorderWidth,
        customSelectedFill: Color? = nil,
        customRestingFill: Color? = nil
    ) -> some View {
        modifier(
            BrowserInteractiveSurfaceModifier(
                isSelected: isSelected,
                selectionEmphasis: selectionEmphasis,
                isHovering: isHovering,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle,
                isPressed: isPressed,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth,
                customSelectedFill: customSelectedFill,
                customRestingFill: customRestingFill
            )
        )
    }

    func browserHoverSurface(
        isSelected: Bool = false,
        cornerRadius: CGFloat = BrowserRadius.compact,
        cornerStyle: RoundedCornerStyle = .continuous,
        isPressed: Bool = false,
        showsRestingSurface: Bool = false,
        selectedBorderColor: Color = BrowserColor.selectedBorder,
        selectedBorderWidth: CGFloat =
            BrowserInteractiveSurfaceMetrics.defaultSelectedBorderWidth
    ) -> some View {
        modifier(
            BrowserHoverSurfaceModifier(
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle,
                isPressed: isPressed,
                showsRestingSurface: showsRestingSurface,
                selectedBorderColor: selectedBorderColor,
                selectedBorderWidth: selectedBorderWidth
            )
        )
    }
}
