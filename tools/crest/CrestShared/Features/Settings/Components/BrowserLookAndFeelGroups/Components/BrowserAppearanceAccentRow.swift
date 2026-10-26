import SwiftUI

/// Whether a surface borrows the Space's accent, and the color it uses instead.
///
/// The color well beside the switch is live only once the switch is off, and
/// holds its place while the Space's accent is in charge, so flipping the
/// switch never moves it.
struct BrowserAppearanceAccentRow: View {
    let color: CrestSettingValue<BrandColor?>
    let fallback: BrandColor
    var identifier: String?

    var body: some View {
        CrestSettingRow("Follow Space accent", setting: color.resettable("Follow Space accent")) {
            HStack(spacing: CrestSettingRowMetrics.controlSpacing) {
                ColorPicker("Custom accent", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .opacity(color.wrappedValue == nil ? 0 : 1)
                    .disabled(color.wrappedValue == nil)
                    .accessibilityHidden(color.wrappedValue == nil)
                Toggle("Follow Space accent", isOn: followsAccent)
                    .labelsHidden()
                    .accessibilityIdentifier(identifier ?? "")
            }
        }
    }

    private var followsAccent: Binding<Bool> {
        Binding(
            get: { color.wrappedValue == nil },
            set: { color.binding.wrappedValue = $0 ? nil : fallback }
        )
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { (color.wrappedValue ?? fallback).color },
            set: { color.binding.wrappedValue = BrandColor(color: $0) }
        )
    }
}
