import SwiftUI

/// How tabs show what their pages are doing, such as playing sound or being
/// shared, on every Space on this device.
struct BrowserTabStatusAppearanceGroup: View {
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    var body: some View {
        CrestSettingsGroup("Tab status", settings: settings) {
            CrestSettingRow("Status", setting: style.resettable("Status")) {
                Picker("Status", selection: style.binding) {
                    Text("Badge").tag(BrowserTabAppearance.StatusStyle.badge)
                    Text("Replace Icon").tag(BrowserTabAppearance.StatusStyle.icon)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Status")
            }
            CrestSettingRow("Audio visualizer", setting: visualizer.resettable("Audio visualizer")) {
                Toggle("Audio visualizer", isOn: visualizer.binding)
                    .labelsHidden()
            }
        }
    }

    private var style: CrestSettingValue<BrowserTabAppearance.StatusStyle> {
        CrestSettingValue($appearance.tabs.statusStyle, default: BrowserLookAndFeelDefaults.tabs.statusStyle)
    }

    private var visualizer: CrestSettingValue<Bool> {
        CrestSettingValue(
            $appearance.tabs.showsAudioVisualizer,
            default: BrowserLookAndFeelDefaults.tabs.showsAudioVisualizer)
    }

    private var settings: [CrestResettableSetting] {
        [style.resettable("Status"), visualizer.resettable("Audio visualizer")]
    }
}
