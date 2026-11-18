import SwiftUI

/// Shared hover and press treatment for compact browser chrome controls.
struct BrowserChromeButtonStyle: ButtonStyle {
    /// The control's fixed size, or `nil` for a tile that takes the size its
    /// label and container give it.
    var controlSize: CGSize? = CGSize(
        width: BrowserLayout.minimumHitTarget,
        height: BrowserLayout.minimumHitTarget
    )
    var cornerRadius = BrowserRadius.compact
    var cornerStyle: RoundedCornerStyle = .continuous
    /// Draws a fixed fill at rest, for a tile that stands on its own rather
    /// than a glyph that only shows a surface under the pointer. It is a fill
    /// rather than the device's material because these tiles sit inside
    /// panels that already wear it, where material on material disappears.
    var showsRestingFill = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(
                BrowserChromeButtonSurface(
                    isPressed: configuration.isPressed,
                    controlSize: controlSize,
                    cornerRadius: cornerRadius,
                    cornerStyle: cornerStyle,
                    showsRestingFill: showsRestingFill
                )
            )
    }
}

private struct BrowserChromeButtonSurface: ViewModifier {
    let isPressed: Bool
    let controlSize: CGSize?
    let cornerRadius: CGFloat
    let cornerStyle: RoundedCornerStyle
    let showsRestingFill: Bool

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                isEnabled
                    ? Color.primary
                    : Color.secondary.opacity(BrowserOpacity.disabled)
            )
            .frame(width: controlSize?.width, height: controlSize?.height)
            .contentShape(.rect(cornerRadius: cornerRadius, style: cornerStyle))
            .browserHoverSurface(
                isSelected: false,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle,
                isPressed: isPressed
            )
            .background {
                if showsRestingFill {
                    RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle).fill(.quaternary)
                }
            }
    }
}
