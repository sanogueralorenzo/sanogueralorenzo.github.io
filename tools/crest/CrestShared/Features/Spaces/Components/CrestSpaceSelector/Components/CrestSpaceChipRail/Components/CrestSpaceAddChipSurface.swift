import SwiftUI

struct CrestSpaceAddChipSurface<LabelContent: View>: View {
    let tint: Color
    let isPressed: Bool
    let label: LabelContent

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: CrestSpaceChipMetrics.cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        label
            .font(
                CrestTypography.sans(
                    CrestButtonMetrics.standardLabelSize,
                    weight: .semibold
                )
            )
            .foregroundStyle(tint)
            .padding(.horizontal, CrestSpaceChipMetrics.horizontalPadding)
            .frame(height: CrestSpaceChipMetrics.height)
            .background(
                tint.opacity(
                    isPressed
                        ? CrestButtonMetrics.tintEmphasizedFill
                        : isHovering ? CrestButtonMetrics.tintRestFill : 0
                ),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    tint.opacity(CrestButtonMetrics.tintEmphasizedStroke),
                    style: StrokeStyle(
                        lineWidth: CrestSpaceChipMetrics.restingStrokeWidth,
                        dash: CrestSpaceChipMetrics.dashPattern
                    )
                )
            }
            .contentShape(
                .rect(
                    cornerRadius: CrestSpaceChipMetrics.cornerRadius,
                    style: .continuous
                )
            )
            .crestFocusShape(shape)
            .crestPressFeedback(
                isPressed: isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }
}

#if DEBUG
    #Preview("Component") {
        CrestSpaceAddChipSurface(tint: .indigo, isPressed: false, label: Label("New Space", systemImage: "plus"))
            .padding()
    }
#endif
