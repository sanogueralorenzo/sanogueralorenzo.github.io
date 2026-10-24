import SwiftUI

enum BrowserSidebarWidgetActionEmphasis {
    case prominent
    case quiet
}

/// Applies Crest action styling at widget-card dimensions.
struct BrowserSidebarWidgetActionButtonStyle: ButtonStyle {
    let emphasis: BrowserSidebarWidgetActionEmphasis

    func makeBody(configuration: Configuration) -> some View {
        BrowserSidebarWidgetActionSurface(
            emphasis: emphasis,
            configuration: configuration
        )
    }
}

private struct BrowserSidebarWidgetActionSurface: View {
    let emphasis: BrowserSidebarWidgetActionEmphasis
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        rendered
            .contentShape(shape)
            .crestFocusShape(shape)
            .crestPressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    @ViewBuilder
    private var rendered: some View {
        switch emphasis {
        case .prominent:
            labeled
                .browserReadableForeground(over: CrestBrandTheme.accent)
                .background(
                    CrestBrandTheme.accent.opacity(
                        configuration.isPressed
                            ? CrestButtonMetrics.pressedFillOpacity
                            : 1
                    ),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        CrestBrandPalette.ink
                            .opacity(CrestButtonMetrics.inkStrokeOpacity),
                        lineWidth: CrestButtonMetrics.strokeWidth
                    )
                }
        case .quiet:
            labeled
                .foregroundStyle(.primary)
                .background {
                    CrestSurfaceLayer(
                        shape: shape,
                        hoverTint: configuration.isPressed || isHovering ? CrestColor.selection : nil
                    )
                }
                .overlay {
                    shape.strokeBorder(
                        CrestColor.subtleBorder,
                        lineWidth: CrestButtonMetrics.strokeWidth
                    )
                }
        }
    }

    private var labeled: some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .labelStyle(.titleAndIcon)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, CrestSpacing.medium)
            .padding(.vertical, CrestSpacing.extraSmall)
            .frame(
                maxWidth: .infinity,
                minHeight: BrowserSidebarWidgetDeckStyle.actionHeight
            )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CrestRadius.control, style: .continuous)
    }
}
