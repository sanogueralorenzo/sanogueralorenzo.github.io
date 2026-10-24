import SwiftUI

/// Reveals a secondary control surface on hover, focus, or press.
struct BrowserSidebarWidgetQuietControlStyle: ButtonStyle {
    var alignment: Alignment = .center

    func makeBody(configuration: Configuration) -> some View {
        BrowserSidebarWidgetQuietControlSurface(
            configuration: configuration,
            alignment: alignment
        )
    }
}

private struct BrowserSidebarWidgetQuietControlSurface: View {
    let configuration: ButtonStyleConfiguration
    let alignment: Alignment

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(BrowserSidebarWidgetDeckStyle.quietControlSymbolFont)
            .foregroundStyle(foreground)
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlDiameter,
                height: BrowserSidebarWidgetDeckStyle.quietControlDiameter
            )
            .background {
                Circle()
                    .fill(emphasis)
            }
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                height: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                alignment: alignment
            )
            .contentShape(.rect)
            .crestFocusShape(Circle())
            .animation(surfaceAnimation, value: isHovering)
            .animation(surfaceAnimation, value: configuration.isPressed)
            .onHover { isHovering = $0 && isEnabled }
    }

    private var foreground: Color {
        isEnabled
            ? .primary
            : .secondary.opacity(CrestOpacity.controlDisabledForeground)
    }

    private var emphasis: Color {
        switch (configuration.isPressed && isEnabled, isHovering) {
        case (true, _):
            CrestColor.selection
        case (false, true):
            CrestColor.hover
        case (false, false):
            .clear
        }
    }

    private var surfaceAnimation: Animation? {
        CrestMotion.surface.unlessReducingMotion(reduceMotion)
    }
}
