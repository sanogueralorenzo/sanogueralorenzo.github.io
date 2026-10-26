import SwiftUI

struct CrestButtonSurface: View {
    let role: CrestButtonRole
    let tint: Color?
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        rendered
            .crestPressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    @ViewBuilder
    private var rendered: some View {
        switch role {
        case .primary:
            primary
        case .secondary:
            secondary
        case .tertiary:
            tertiary
        case .destructive:
            destructive
        case .icon(let diameter, let isProminent):
            icon(diameter: diameter, isProminent: isProminent)
        }
    }

    private var primary: some View {
        configuration.label
            .font(
                CrestTypography.sans(
                    CrestButtonMetrics.prominentLabelSize,
                    weight: .bold
                )
            )
            .foregroundStyle(CrestBrandPalette.ink)
            .padding(.horizontal, CrestButtonMetrics.prominentHorizontalPadding)
            .frame(minHeight: CrestButtonMetrics.prominentHeight)
            .background {
                Capsule().fill(
                    (tint ?? CrestBrandPalette.butter)
                        .opacity(
                            configuration.isPressed
                                ? CrestButtonMetrics.pressedFillOpacity
                                : 1
                        )
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    CrestBrandPalette.ink
                        .opacity(CrestButtonMetrics.inkStrokeOpacity),
                    lineWidth: CrestButtonMetrics.strokeWidth
                )
            }
            .crestCapsuleInteractionShape()
    }

    private var secondary: some View {
        configuration.label
            .font(
                CrestTypography.sans(
                    CrestButtonMetrics.standardLabelSize,
                    weight: .semibold
                )
            )
            .foregroundStyle(CrestBrandTheme.textDisplay)
            .padding(.horizontal, CrestButtonMetrics.standardHorizontalPadding)
            .frame(minHeight: CrestButtonMetrics.standardHeight)
            .background {
                Capsule().fill(
                    configuration.isPressed || isHovering
                        ? CrestBrandTheme.surface
                        : CrestBrandTheme.canvas
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    CrestBrandTheme.line,
                    lineWidth: CrestButtonMetrics.strokeWidth
                )
            }
            .crestCapsuleInteractionShape()
    }

    private var destructive: some View {
        let tint = resolvedTint
        return configuration.label
            .font(
                CrestTypography.sans(
                    CrestButtonMetrics.standardLabelSize,
                    weight: .semibold
                )
            )
            .foregroundStyle(resolvedTextTint)
            .padding(.horizontal, CrestButtonMetrics.standardHorizontalPadding)
            .frame(minHeight: CrestButtonMetrics.standardHeight)
            .background {
                Capsule().fill(tint.opacity(tintedFillOpacity(isEmphasized: false)))
            }
            .overlay {
                Capsule().strokeBorder(
                    tint.opacity(CrestButtonMetrics.tintEmphasizedStroke),
                    lineWidth: CrestButtonMetrics.strokeWidth
                )
            }
            .crestCapsuleInteractionShape()
    }

    private var tertiary: some View {
        configuration.label
            .font(CrestTypography.controlTitle)
            .foregroundStyle(resolvedTextTint)
            .padding(.horizontal, CrestButtonMetrics.quietHorizontalPadding)
            .frame(minHeight: CrestLayout.minimumHitTarget)
            .crestInteractiveSurface(
                isSelected: false,
                isHovering: isHovering,
                cornerRadius: CrestRadius.compact,
                isPressed: configuration.isPressed
            )
            .contentShape(.rect(cornerRadius: CrestRadius.compact, style: .continuous))
            .crestFocusShape(
                RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
            )
    }

    private func icon(diameter: CGFloat, isProminent: Bool) -> some View {
        let tint = resolvedTint
        let hitTarget = max(diameter, CrestLayout.minimumHitTarget)
        return configuration.label
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(
                    tint.opacity(tintedFillOpacity(isEmphasized: isProminent))
                )
            }
            .overlay {
                Circle().strokeBorder(
                    tint.opacity(
                        isProminent
                            ? CrestButtonMetrics.tintEmphasizedStroke
                            : CrestButtonMetrics.tintRestStroke
                    ),
                    lineWidth: isProminent
                        ? CrestButtonMetrics.prominentStrokeWidth
                        : CrestButtonMetrics.quietStrokeWidth
                )
            }
            .frame(width: hitTarget, height: hitTarget)
            .contentShape(.rect)
            .crestFocusShape(Circle())
    }

    private var resolvedTint: Color { tint ?? CrestBrandTheme.accent }
    private var resolvedTextTint: Color { tint ?? CrestBrandTheme.accentText }

    private func tintedFillOpacity(isEmphasized: Bool) -> Double {
        switch (configuration.isPressed, isEmphasized || isHovering) {
        case (true, _):
            CrestButtonMetrics.tintPressedFill
        case (false, true):
            CrestButtonMetrics.tintEmphasizedFill
        case (false, false):
            CrestButtonMetrics.tintRestFill
        }
    }
}

#if DEBUG
    #Preview("Button roles") {
        VStack(spacing: 16) {
            Button("Save Setup") {}.buttonStyle(.crestPrimary)
            Button("Back") {}.buttonStyle(.crestSecondary)
            Button("Delete") {}.buttonStyle(.crestDestructive)
            Button("Manage Filter Lists") {}.buttonStyle(.crestTertiary)
            Button("Disabled") {}.buttonStyle(.crestPrimary).disabled(true)
        }.padding().frame(width: 300)
    }
#endif
