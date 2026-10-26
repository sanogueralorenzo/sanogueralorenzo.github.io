import SwiftUI

struct BrowserTranslationButton: View {
    let translation: BrowserPageTranslation

    var body: some View {
        Button(action: translation.performAction) {
            Image(systemName: "translate")
                .foregroundStyle(translation.isTranslated ? CrestBrandTheme.accent : .primary)
                .overlay(alignment: .topTrailing) {
                    if translation.isWorking {
                        ProgressView().controlSize(.mini).offset(x: 6, y: -5)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(translation.actionTitle)
        .accessibilityValue(translation.status)
        .accessibilityIdentifier("page-translation-button")
        .help(translation.status.isEmpty ? translation.actionTitle : translation.status)
    }
}
