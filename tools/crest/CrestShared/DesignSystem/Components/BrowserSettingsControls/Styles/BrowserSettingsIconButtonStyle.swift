import SwiftUI

struct BrowserSettingsIconButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(
                width: BrowserSettingsControlMetrics.minimumTouchTarget,
                height: BrowserSettingsControlMetrics.minimumTouchTarget
            )
            .background(
                tint.opacity(
                    configuration.isPressed
                        ? BrowserSettingsControlMetrics.iconPressedFillOpacity
                        : BrowserSettingsControlMetrics.restingFillOpacity
                ),
                in: RoundedRectangle(
                    cornerRadius: BrowserSettingsControlMetrics.cornerRadius,
                    style: .continuous
                )
            )
            .contentShape(.rect)
            .scaleEffect(
                configuration.isPressed
                    ? BrowserSettingsControlMetrics.iconPressedScale
                    : 1
            )
            .opacity(
                isEnabled ? 1 : BrowserSettingsControlMetrics.iconDisabledOpacity
            )
            .animation(
                CrestMotion.compactPress.unlessReducingMotion(reduceMotion),
                value: configuration.isPressed
            )
    }
}
