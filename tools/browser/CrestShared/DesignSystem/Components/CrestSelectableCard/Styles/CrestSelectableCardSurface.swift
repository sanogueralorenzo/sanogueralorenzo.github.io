import SwiftUI

struct CrestSelectableCardSurface: View {
    let isSelected: Bool
    let tint: Color?
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    var body: some View {
        let tint = tint ?? CrestBrandTheme.accent
        let shape = RoundedRectangle(
            cornerRadius: CrestSelectableCardMetrics.cornerRadius,
            style: .continuous
        )

        configuration.label
            .padding(CrestSelectableCardMetrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(tint: tint), in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? tint : CrestBrandTheme.line,
                    lineWidth: borderWidth
                )
            }
            .contentShape(
                .rect(
                    cornerRadius: CrestSelectableCardMetrics.cornerRadius,
                    style: .continuous
                )
            )
            .crestFocusShape(shape)
            .crestPressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .animation(
                CrestMotion.press.unlessReducingMotion(reduceMotion),
                value: isSelected
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    private var borderWidth: CGFloat {
        switch (isSelected, contrast) {
        case (true, _), (false, .increased):
            CrestSelectableCardMetrics.selectedBorderWidth
        case (false, _):
            CrestSelectableCardMetrics.restingBorderWidth
        }
    }

    private func background(tint: Color) -> Color {
        switch (isSelected, configuration.isPressed, isHovering) {
        case (true, true, _):
            tint.opacity(CrestButtonMetrics.tintEmphasizedFill)
        case (true, false, _):
            tint.opacity(CrestSelectableCardMetrics.selectedFillOpacity)
        case (false, true, _):
            CrestColor.selection
        case (false, false, true):
            CrestColor.hover
        case (false, false, false):
            CrestColor.chromeSurface
        }
    }
}

#if DEBUG
    #Preview("Card surface") {
        @Previewable @State var selected = false
        CrestSelectableCard(isSelected: selected, accessibilityLabel: Text("Banner"), action: { selected.toggle() }) {
            Label("Banner", systemImage: "flag.fill").frame(maxWidth: .infinity, alignment: .leading)
        }.padding().frame(width: 320)
    }
#endif
