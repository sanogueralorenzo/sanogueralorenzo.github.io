import SwiftUI

/// How new, pinned and saved tabs behave, Split View focus, and the sidebar's
/// optional widgets.
struct BrowserTabsSettingsPane: View {
    let browser: BrowserStore

    @Environment(\.browserSidebarWidgetRuntime) private var sidebarWidgets
    @Bindable private var appPreferences = BrowserAppPreferenceStore.shared

    var body: some View {
        BrowserSettingsPane(.tabs) {
            BrowserNewTabSettingsSection(preferences: browser.linkPreferences)
            BrowserDurableTabSettingsSection(preferences: appPreferences)
            #if os(macOS)
                BrowserSplitFocusSettingsSection()
            #endif
            if let sidebarWidgets {
                BrowserSidebarWidgetSettingsSection(runtime: sidebarWidgets)
            }
        }
    }
}

struct BrowserNewTabSettingsSection: View {
    static let controlIdentifier =
        "focus-new-tabs-opened-from-links-toggle"

    let preferences: BrowserLinkPreferenceStore

    var body: some View {
        Section {
            Toggle(
                "Switch to tabs opened from links",
                isOn: preferences.binding(.focusesNewTabs, reading: \.focusesNewTabs)
            )
            .accessibilityIdentifier(Self.controlIdentifier)

            Toggle(
                "Follow tabs moved to another Space",
                isOn: preferences.binding(.followsMovedTabs, reading: \.followsMovedTabs)
            )
            .accessibilityIdentifier("follow-tabs-moved-to-another-space-toggle")
        } header: {
            Text("New tabs")
        } footer: {
            CrestFormFootnote("Hold Shift as you open a link to do the opposite.")
        }
    }
}

struct BrowserSidebarWidgetSettingsSection: View {
    let runtime: BrowserSidebarWidgetRuntime

    var body: some View {
        let registrations = runtime.userControllableRegistrations()
        if !registrations.isEmpty {
            Section("Sidebar widgets") {
                ForEach(registrations) { registration in
                    Toggle(
                        registration.settingsTitle,
                        isOn: enabledBinding(for: registration.id)
                    )
                    .accessibilityIdentifier(
                        "sidebar-widget-\(registration.id.rawValue)-toggle"
                    )
                }
            }
        }
    }

    private func enabledBinding(
        for kindID: BrowserSidebarWidgetKindID
    ) -> Binding<Bool> {
        Binding {
            runtime.isWidgetEnabled(kindID)
        } set: { isEnabled in
            runtime.setWidgetEnabled(isEnabled, for: kindID)
        }
    }
}
