import SwiftUI

/// Browser import, data portability, and advanced engine controls.
struct BrowserAdvancedSettingsPane: View {
    let browser: BrowserStore
    let importActions: [BrowserAdvancedImportAction]
    var showsMacOSImportRequirement = false
    /// Opens Feature Flags, where a shell keeps it under this pane.
    var openFeatureFlags: (() -> Void)? = nil

    var body: some View {
        BrowserSettingsPane(.advanced) {
            BrowserAdvancedImportSection(importActions: importActions)
            if let openFeatureFlags {
                Section {
                    Button(action: openFeatureFlags) {
                        LabeledContent(String(localized: BrowserSettingsDestination.featureFlags.title)) {
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-featureFlags")
                }
            }
            BrowserDataPortabilitySection(
                browser: browser,
                showsMacOSImportRequirement: showsMacOSImportRequirement
            )
        }
    }
}
