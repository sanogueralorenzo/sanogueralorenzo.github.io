import SwiftUI

struct BrowserSettingsLabeledActionButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, BrowserSettingsControlMetrics.horizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: BrowserSettingsControlMetrics.labeledActionHeight
            )
            .fixedSize(horizontal: false, vertical: true)
            .background(
                tint.opacity(
                    configuration.isPressed
                        ? BrowserSettingsControlMetrics.labeledPressedFillOpacity
                        : BrowserSettingsControlMetrics.restingFillOpacity
                ),
                in: RoundedRectangle(
                    cornerRadius: BrowserSettingsControlMetrics.cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: BrowserSettingsControlMetrics.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    tint.opacity(BrowserSettingsControlMetrics.labeledBorderOpacity),
                    lineWidth: BrowserSettingsControlMetrics.borderWidth
                )
            }
            .contentShape(.rect)
            .scaleEffect(
                configuration.isPressed
                    ? BrowserSettingsControlMetrics.labeledPressedScale
                    : 1
            )
            .opacity(
                isEnabled ? 1 : BrowserSettingsControlMetrics.labeledDisabledOpacity
            )
            .animation(
                CrestMotion.compactPress.unlessReducingMotion(reduceMotion),
                value: configuration.isPressed
            )
    }
}
