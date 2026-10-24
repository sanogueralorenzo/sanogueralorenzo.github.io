import SwiftUI

/// The window's frame: how much of the Space shows around a page, which side
/// the sidebar sits on, how its Space icons are sized, and the accent its tabs
/// and address field wear.
///
/// The desktop hands in the choices only it has — focused-window transparency
/// and Space page motion — as extra rows and the settings that go with them, so
/// the group's own Reset covers them too.
struct BrowserWindowAppearanceGroup<Extra: View>: View {
    // MARK: - Variables

    var space: BrowserSpaceAppearance?
    var showsPreview = false
    var extraSettings: [CrestResettableSetting] = []
    @ViewBuilder var extraRows: () -> Extra

    @AppStorage(BrowserChromeAppearancePreference.borderWidthKey, store: BrowserChromeAppearancePreference.defaults)
    private var borderWidth = BrowserLookAndFeelDefaults.windowBorderWidth
    @AppStorage(BrowserChromeAppearancePreference.sidebarOnRightKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarOnRight = BrowserLookAndFeelDefaults.sidebarOnRight
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    // MARK: - Actions - Drawing

    var body: some View {
        CrestSettingsGroup(
            "Window",
            settings: settings
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .window)
            }
        } content: {
            CrestSettingSlider(
                "Window border",
                value: border,
                range: BrowserChromeAppearance.borderWidthRange,
                readout: .points(zero: "Borderless"),
                identifier: "window-border-width"
            )
            CrestSettingSlider(
                "Material",
                value: material,
                range: 0...Double(CrestSurfaceMaterial.all.count - 1),
                step: 1,
                readout: CrestSettingSliderReadout {
                    String(localized: CrestSurfaceMaterial.at(position: Int($0.rounded())).title)
                },
                identifier: "surface-material"
            )
            CrestSettingRow("Sidebar on right", setting: sidebar.resettable("Sidebar on right")) {
                Toggle("Sidebar on right", isOn: sidebar.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-on-right")
            }
            CrestSettingRow(
                "Fit Space icons to sidebar", setting: fitsSpaceIcons.resettable("Fit Space icons to sidebar")
            ) {
                Toggle("Fit Space icons to sidebar", isOn: fitsSpaceIcons.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("space-icons-fit-sidebar")
            }
            CrestSettingSlider(
                "Space icon size",
                value: spaceIconScale,
                range: BrowserSpaceIconSizing.scaleRange,
                step: BrowserSpaceIconSizing.scaleStep,
                identifier: "space-icon-size"
            )
            .disabled(appearance.spaceIconSizing.fitsStrip)
            BrowserAppearanceAccentRow(
                color: accent,
                fallback: space?.branding.primaryColor ?? .indigo,
                identifier: "follows-space-accent"
            )
            extraRows()
        }
    }

    // MARK: - Actions - Settings

    private var border: CrestSettingValue<Double> {
        CrestSettingValue($borderWidth, default: BrowserLookAndFeelDefaults.windowBorderWidth)
    }

    /// The sidebar's layer material, as a position from Ultra Thin to Ultra Thick.
    private var material: CrestSettingValue<Double> {
        CrestSettingValue(
            Binding(
                get: { Double(appearance.surfaceMaterial.position) },
                set: { appearance.surfaceMaterial = .at(position: Int($0.rounded())) }
            ),
            default: Double(BrowserLookAndFeelDefaults.surfaceMaterial.position)
        )
    }

    private var sidebar: CrestSettingValue<Bool> {
        CrestSettingValue($sidebarOnRight, default: BrowserLookAndFeelDefaults.sidebarOnRight)
    }

    /// Whether the Space switcher fits its icons to the sidebar, or keeps the
    /// size below.
    private var fitsSpaceIcons: CrestSettingValue<Bool> {
        CrestSettingValue(
            Binding(
                get: { appearance.spaceIconSizing.fitsStrip },
                set: { appearance.spaceIconSizing = $0 ? .automatic : .manual }
            ),
            default: BrowserLookAndFeelDefaults.spaceIconSizing.fitsStrip
        )
    }

    private var spaceIconScale: CrestSettingValue<Double> {
        CrestSettingValue($appearance.spaceIconScale, default: BrowserLookAndFeelDefaults.spaceIconScale)
    }

    /// One accent for the selected tabs, pins and the address field, which
    /// keep their own stored colors.
    private var accent: CrestSettingValue<BrandColor?> {
        CrestSettingValue(
            Binding(
                get: { appearance.tabs.color ?? appearance.address.color },
                set: { color in
                    appearance.tabs.color = color
                    appearance.address.color = color
                }
            )
        )
    }

    private var settings: [CrestResettableSetting] {
        [
            border.resettable("Window border"), material.resettable("Material"),
            sidebar.resettable("Sidebar on right"), fitsSpaceIcons.resettable("Fit Space icons to sidebar"),
            spaceIconScale.resettable("Space icon size"),
            accent.resettable("Follow Space accent"),
        ] + extraSettings
    }
}
