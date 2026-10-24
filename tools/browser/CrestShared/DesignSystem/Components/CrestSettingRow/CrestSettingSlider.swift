import SwiftUI

/// How a slider names its live value.
struct CrestSettingSliderReadout: Sendable {
    let label: @Sendable (Double) -> String

    init(label: @escaping @Sendable (Double) -> String) {
        self.label = label
    }

    /// A plain percentage of the control's range.
    static let percent = CrestSettingSliderReadout {
        $0.formatted(.percent.precision(.fractionLength(0)))
    }

    /// A percentage whose ends have names of their own, as "Subtle" and
    /// "Opaque" do for a folder's color.
    static func percent(zero: LocalizedStringResource, full: LocalizedStringResource) -> Self {
        CrestSettingSliderReadout { value in
            if value <= 0 { return String(localized: zero) }
            if value >= 1 { return String(localized: full) }
            return value.formatted(.percent.precision(.fractionLength(0)))
        }
    }

    /// A point measurement.
    static let points = CrestSettingSliderReadout { String(localized: "\(Int($0.rounded())) pt") }

    /// A point measurement, such as the window border, whose zero is a word.
    static func points(zero: LocalizedStringResource) -> Self {
        CrestSettingSliderReadout { value in
            value <= 0 ? String(localized: zero) : String(localized: "\(Int(value.rounded())) pt")
        }
    }
}

/// Shared by settings and Space appearance. On the Mac the title and reset sit
/// on one line with a fixed track and its live value; narrow screens keep the
/// value above a full-width track. Readouts can name endpoints such as
/// "Borderless".
struct CrestSettingSlider: View {
    private let title: LocalizedStringKey
    private let value: CrestSettingValue<Double>
    private let range: ClosedRange<Double>
    private let step: Double?
    private let readout: CrestSettingSliderReadout
    private let identifier: String?
    private let onEditingChanged: (Bool) -> Void

    init(
        _ title: LocalizedStringKey,
        value: CrestSettingValue<Double>,
        range: ClosedRange<Double> = 0...1,
        step: Double? = nil,
        readout: CrestSettingSliderReadout = .percent,
        identifier: String? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.readout = readout
        self.identifier = identifier
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        #if os(macOS)
            CrestSettingRow(title, setting: value.resettable(title)) {
                HStack(spacing: CrestSpacing.small) {
                    slider
                        .frame(width: CrestSettingRowMetrics.inlineSliderWidth)
                    Text(valueLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: CrestSettingRowMetrics.sliderReadoutWidth, alignment: .trailing)
                }
            }
        #else
            VStack(spacing: CrestSettingRowMetrics.sliderSpacing) {
                CrestSettingRow(title, setting: value.resettable(title)) {
                    Text(valueLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                slider
            }
            .frame(maxWidth: .infinity)
        #endif
    }

    private var slider: some View {
        Group {
            if let step {
                Slider(value: value.binding, in: range, step: step, onEditingChanged: onEditingChanged) { Text(title) }
            } else {
                Slider(value: value.binding, in: range, onEditingChanged: onEditingChanged) { Text(title) }
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(valueLabel))
        .accessibilityIdentifier(identifier ?? "")
    }

    private var valueLabel: String { readout.label(value.wrappedValue) }
}

#if DEBUG
    #Preview("Adjust and reset") {
        @Previewable @State var opacity = 0.65
        Form {
            CrestSettingSlider("Opacity", value: CrestSettingValue($opacity, default: 1))
        }.crestSettingsForm().frame(width: 420, height: 180)
    }
#endif
