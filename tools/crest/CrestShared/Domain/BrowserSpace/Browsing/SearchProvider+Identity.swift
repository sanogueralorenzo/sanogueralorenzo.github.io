import Foundation

extension SearchProvider: Identifiable {
    // MARK: - Variables

    var id: String {
        name
    }

    /// Whether a person added the provider rather than Crest shipping it.
    var isCustom: Bool {
        customID != nil
    }

    /// The website whose icon stands for a provider without a logo.
    var iconPageURL: URL? {
        guard logo == nil, !site.isEmpty else { return nil }
        return URL(string: "https://\(site)/")
    }

    /// What the palette's row for the provider says, as "Search Google" or "Ask Claude".
    var actionTitle: String {
        kind == .assistant
            ? String(localized: "Ask \(title)", comment: "A palette row that asks an AI assistant.")
            : String(localized: "Search \(title)", comment: "A palette row that searches a search engine or website.")
    }

    // MARK: - Initializers

    /// A provider a Space carries that this device does not keep, named as the
    /// core names one a person added.
    init(carried: CustomSearchProvider) {
        let template = carried.searchURLTemplate
            .replacingOccurrences(of: "{searchTerms}", with: "crest").replacingOccurrences(of: "%s", with: "crest")
        let host = URLComponents(string: template)?.host ?? ""
        self.init(
            name: Self.customPrefix + carried.id.coreIdentifier, title: carried.name, kind: carried.kind,
            shortcuts: carried.shortcuts, searchTemplate: carried.searchURLTemplate,
            suggestionTemplate: carried.suggestionURLTemplate,
            color: carried.color ?? BrandColor(red: 0.45, green: 0.48, blue: 0.52),
            logo: nil, builtIn: nil, customID: carried.id,
            site: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
    }
}

extension SearchProvider: Hashable {
    // MARK: - Actions - Identity

    /// Providers that are equal share a name, so the name alone hashes them.
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
