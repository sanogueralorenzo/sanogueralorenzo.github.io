import SwiftUI

struct BrowserTranslationSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared
    @State private var languages: [Locale.Language] = []

    private var exclusionLanguages: [String] {
        Set(languages.compactMap { $0.languageCode?.identifier }).sorted {
            languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending
        }
    }

    var body: some View {
        Section("Translate") {
            Toggle("Translate Automatically", isOn: $preferences.translateAutomatically)
                .accessibilityIdentifier("translate-automatically")
            Picker("Translate Language", selection: $preferences.translationLanguage) {
                if !languages.contains(where: { $0.minimalIdentifier == preferences.translationLanguage }) {
                    Text(languageName(preferences.translationLanguage)).tag(preferences.translationLanguage)
                }
                ForEach(languages, id: \.minimalIdentifier) { language in
                    Text(languageName(language.minimalIdentifier)).tag(language.minimalIdentifier)
                }
            }
            .accessibilityIdentifier("translation-language-picker")
            LabeledContent("Excluded Languages") {
                Menu {
                    ForEach(exclusionLanguages, id: \.self) { identifier in
                        Toggle(languageName(identifier), isOn: exclusion(identifier))
                    }
                } label: {
                    Text(
                        preferences.excludedTranslationLanguages.isEmpty
                            ? String(localized: "None")
                            : preferences.excludedTranslationLanguages.map(languageName).joined(separator: ", ")
                    )
                    .lineLimit(1)
                }
                .disabled(languages.isEmpty)
                .accessibilityIdentifier("excluded-translation-languages")
            }
        }
        .task {
            languages = await BrowserTranslationPreference.languages().all.sorted {
                languageName($0.minimalIdentifier).localizedStandardCompare(languageName($1.minimalIdentifier))
                    == .orderedAscending
            }
        }
    }

    private func exclusion(_ identifier: String) -> Binding<Bool> {
        Binding(
            get: { preferences.excludedTranslationLanguages.contains(identifier) },
            set: { excluded in
                var identifiers = Set(preferences.excludedTranslationLanguages)
                if excluded { identifiers.insert(identifier) } else { identifiers.remove(identifier) }
                preferences.excludedTranslationLanguages = identifiers.sorted()
            })
    }

    private func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
