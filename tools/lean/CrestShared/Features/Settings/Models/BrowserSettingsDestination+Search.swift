import Foundation

extension BrowserSettingsDestination {
    /// The concrete localized haystack used only while filtering Settings.
    /// Presentation remains deferred through ``LocalizedStringResource``.
    private func searchIndex(locale: Locale) -> String {
        [title, navigationTitle, subtitle, searchTerms]
            .map { resource in
                var localizedResource = resource
                localizedResource.locale = locale
                return String(localized: localizedResource)
            }
            .joined(separator: " ")
    }

    func matchesSearchQuery(_ query: String, locale: Locale) -> Bool {
        searchIndex(locale: locale).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        ) != nil
    }
}

extension BrowserSettingsDestination {
    /// Every settings page as the command palette offers it: by its name,
    /// with its title and the words a person might type to find it.
    static var palettePages: [PaletteSettingsPage] {
        all.map {
            PaletteSettingsPage(
                name: $0.name, title: String(localized: $0.title),
                terms: [String(localized: $0.subtitle), String(localized: $0.searchTerms)].joined(separator: " "))
        }
    }
}
