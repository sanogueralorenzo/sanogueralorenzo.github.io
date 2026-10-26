import SwiftUI

/// Tabs, pins, and the shape they share, on every Space on this device.
struct BrowserTabAppearanceGroup: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    var body: some View {
        CrestSettingsGroup(
            "Tabs and pins",
            settings: settings
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .tabs)
            }
        } content: {
            BrowserAppearancePresetPicker(
                "Corner radius",
                value: cornerRadius,
                presets: BrowserAppearancePresets.cornerRadius,
                tolerance: BrowserAppearancePresets.cornerRadiusTolerance,
                identifier: "tab-corner-radius"
            )
            BrowserAppearancePresetPicker(
                "Tab scale",
                value: scale,
                presets: BrowserAppearancePresets.tabScale,
                tolerance: BrowserAppearancePresets.tabScaleTolerance,
                identifier: "tab-scale"
            )
            CrestSettingRow("Pin layout", setting: columns.resettable("Pin layout")) {
                Picker("Pin layout", selection: columns.binding) {
                    Text("Balanced rows").tag(0)
                    Text("One per row").tag(1)
                    ForEach(2...6, id: \.self) { Text("Up to \($0) per row").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Pin layout")
            }
            CrestSettingRow(
                "Stretch pins to fill the row", setting: fillsRow.resettable("Stretch pins to fill the row")
            ) {
                Toggle("Stretch pins to fill the row", isOn: fillsRow.binding)
                    .labelsHidden()
            }
            CrestSettingRow("Color borders", setting: borders.resettable("Color borders")) {
                Picker("Color borders", selection: borders.binding) {
                    Text("Selected").tag(BrowserTabAppearance.Borders.selected)
                    Text("Pins").tag(BrowserTabAppearance.Borders.pinned)
                    Text("All tabs").tag(BrowserTabAppearance.Borders.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Color borders")
            }
            CrestSettingRow(
                "Accent outline on selected tabs", setting: outlines.resettable("Accent outline on selected tabs")
            ) {
                Toggle("Accent outline on selected tabs", isOn: outlines.binding)
                    .labelsHidden()
            }
            CrestSettingRow("Website colors for pins", setting: websiteColors.resettable("Website colors for pins")) {
                Toggle("Website colors for pins", isOn: websiteColors.binding)
                    .labelsHidden()
            }
            CrestSettingRow("Dim unloaded tabs", setting: dimming.resettable("Dim unloaded tabs")) {
                Toggle("Dim unloaded tabs", isOn: dimming.binding)
                    .labelsHidden()
            }
            CrestSettingSlider("Pinned fill", value: pinFill, readout: .percent(zero: "None", full: "Strong"))
            CrestSettingSlider("Selected tab glow", value: pinGlow, readout: .percent(zero: "None", full: "Strong"))
            CrestSettingSlider("Hover tint", value: hoverFill, readout: .percent(zero: "Neutral", full: "Accent"))
        }
    }

    private var cornerRadius: CrestSettingValue<Double> {
        CrestSettingValue($appearance.cornerRadius, default: BrowserLookAndFeelDefaults.cornerRadius)
    }

    private var scale: CrestSettingValue<Double> {
        CrestSettingValue($appearance.tabScale, default: BrowserLookAndFeelDefaults.tabScale)
    }

    private var columns: CrestSettingValue<Int> {
        CrestSettingValue($appearance.pinColumns, default: BrowserLookAndFeelDefaults.pinColumns)
    }

    private var fillsRow: CrestSettingValue<Bool> {
        CrestSettingValue($appearance.pinsFillRow, default: BrowserLookAndFeelDefaults.pinsFillRow)
    }

    private var borders: CrestSettingValue<BrowserTabAppearance.Borders> {
        CrestSettingValue($appearance.tabs.borders, default: BrowserLookAndFeelDefaults.tabs.borders)
    }

    private var outlines: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.tabs.outlinesSelectedTabs,
            default: BrowserLookAndFeelDefaults.tabs.outlinesSelectedTabs)
    }

    private var websiteColors: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.tabs.usesWebsitePinColor,
            default: BrowserLookAndFeelDefaults.tabs.usesWebsitePinColor)
    }

    private var dimming: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.tabs.dimsUnloadedTabs,
            default: BrowserLookAndFeelDefaults.tabs.dimsUnloadedTabs)
    }

    private var pinFill: CrestSettingValue<Double> {
        CrestSettingValue($appearance.tabs.pinFill, default: BrowserLookAndFeelDefaults.tabs.pinFill)
    }

    private var pinGlow: CrestSettingValue<Double> {
        CrestSettingValue($appearance.tabs.pinGlow, default: BrowserLookAndFeelDefaults.tabs.pinGlow)
    }

    private var hoverFill: CrestSettingValue<Double> {
        CrestSettingValue($appearance.tabs.hoverFill, default: BrowserLookAndFeelDefaults.tabs.hoverFill)
    }

    private var settings: [CrestResettableSetting] {
        [
            cornerRadius.resettable("Corner radius"),
            scale.resettable("Tab scale"),
            columns.resettable("Pin layout"),
            fillsRow.resettable("Stretch pins to fill the row"),
            borders.resettable("Color borders"),
            outlines.resettable("Accent outline on selected tabs"),
            websiteColors.resettable("Website colors for pins"),
            dimming.resettable("Dim unloaded tabs"),
            pinFill.resettable("Pinned fill"),
            pinGlow.resettable("Selected tab glow"),
            hoverFill.resettable("Hover tint"),
        ]
    }
}
