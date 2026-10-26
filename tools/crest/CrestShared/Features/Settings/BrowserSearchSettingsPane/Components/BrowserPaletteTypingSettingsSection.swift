import SwiftUI

/// How the palette completes and learns as a person types, and clearing what
/// it learned.
struct BrowserPaletteTypingSettingsSection: View {
    @Bindable var preferences: BrowserAppPreferenceStore
    let browser: BrowserStore

    @State private var confirmsClearing = false

    var body: some View {
        Section {
            Toggle("Complete addresses inline", isOn: $preferences.palette.completesInline)
                .accessibilityIdentifier("palette-completes-inline")
            Toggle("Learn from my choices", isOn: $preferences.palette.learnsChoices)
                .accessibilityIdentifier("palette-learns-choices")
            Button("Clear Learned Choices…", role: .destructive) {
                confirmsClearing = true
            }
            .accessibilityIdentifier("palette-clear-learned")
        } header: {
            Text("Typing")
        } footer: {
            CrestFormFootnote("Learned choices stay on this device.")
        }
        .confirmationDialog("Clear what the palette learned?", isPresented: $confirmsClearing) {
            Button("Clear Learned Choices", role: .destructive) {
                _ = try? browser.core.send(ClearPaletteChoices())
            }
        } message: {
            Text("The palette forgets which results you chose for what you typed.")
        }
    }
}
