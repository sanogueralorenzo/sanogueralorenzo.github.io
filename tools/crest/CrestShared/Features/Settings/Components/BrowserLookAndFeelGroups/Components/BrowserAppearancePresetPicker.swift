import SwiftUI

/// Named stops on a continuous value. The stops are the whole control.
///
/// A value stored by an earlier release can sit between two presets; the row
/// then selects nothing and says "Custom" beside the segments rather than
/// quietly rounding it. That word keeps its place while hidden, so choosing a
/// preset never moves the control.
struct BrowserAppearancePresetPicker: View {
    private let title: LocalizedStringKey
    private let value: CrestSettingValue<Double>
    private let presets: [BrowserAppearancePreset]
    private let tolerance: Double
    private let identifier: String?

    init(
        _ title: LocalizedStringKey,
        value: CrestSettingValue<Double>,
        presets: [BrowserAppearancePreset],
        tolerance: Double,
        identifier: String? = nil
    ) {
        self.title = title
        self.value = value
        self.presets = presets
        self.tolerance = tolerance
        self.identifier = identifier
    }

    var body: some View {
        CrestSettingRow(title, setting: value.resettable(title)) {
            HStack(spacing: CrestSettingRowMetrics.controlSpacing) {
                Text("Custom")
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
                    .opacity(match == nil ? 1 : 0)
                    .accessibilityHidden(true)
                Picker(title, selection: selection) {
                    ForEach(presets) { preset in
                        Text(preset.title).tag(Optional(preset.id))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(match?.title ?? String(localized: "Custom")))
                .accessibilityIdentifier(identifier ?? "")
            }
        }
    }

    private var match: BrowserAppearancePreset? {
        BrowserAppearancePresets.match(value.wrappedValue, in: presets, tolerance: tolerance)
    }

    private var selection: Binding<String?> {
        Binding(
            get: { match?.id },
            set: { identifier in
                guard let preset = presets.first(where: { $0.id == identifier }) else { return }
                value.binding.wrappedValue = preset.value
            }
        )
    }
}
