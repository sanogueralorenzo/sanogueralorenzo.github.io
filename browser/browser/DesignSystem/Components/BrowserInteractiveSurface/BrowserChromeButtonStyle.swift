import SwiftUI

struct BrowserChromeButtonStyle: ButtonStyle {
    var controlSize: CGSize? = CGSize(
        width: BrowserLayout.minimumHitTarget,
        height: BrowserLayout.minimumHitTarget
    )
    var cornerRadius = BrowserRadius.compact
    var cornerStyle: RoundedCornerStyle = .continuous
    /// Use a solid fill because stacked materials can disappear.
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
