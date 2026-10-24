import Foundation
import Observation

/// This device's search providers, which the core keeps in its device store
/// and never syncs: every built-in, on or off with the person's shortcuts and
/// options, the providers the person added, and the default search. The
/// catalog reads them as the core publishes them and sends each edit as an
/// intent; a refused edit throws the core's rejection.
@MainActor
@Observable
final class BrowserSearchCatalog {
    // MARK: - Variables

    @ObservationIgnored private let core: CrestCore

    private var published: SearchCatalogChanged? { core.state.searchCatalog }

    /// Every provider as the device searches with it, the built-ins first.
    var providers: [SearchProvider] { published?.providers ?? [] }

    /// What a Space that follows the default searches with.
    var defaultProvider: SearchProvider? { published?.default }

    /// What a private window's Space that follows the default searches with.
    var privateDefaultProvider: SearchProvider? { published?.privateDefault }

    /// Whether the default search suggests searches as a person types.
    var suggestionsEnabled: Bool { published?.catalog.suggestionsEnabled ?? false }

    /// The providers a default may be, of every kind that may be one.
    var defaultChoices: [SearchProvider] {
        providers.filter {
            $0.kind.canBeDefault && (isEnabled($0) || $0 == defaultProvider || $0 == privateDefaultProvider)
        }
    }

    // MARK: - Initializers

    /// A catalog over `core`, which has the core publish the catalog when it
    /// has not yet.
    init(core: CrestCore) {
        self.core = core
        if core.state.searchCatalog == nil { Self.restore(into: core) }
    }

    // MARK: - Actions - Launch

    /// Has `core` keep the device's catalog for this device's language and
    /// region and publish it; the first time it starts from the built-ins and
    /// what the Spaces chose. A launch does this before any window opens.
    static func restore(into core: CrestCore, locale: Locale = .current) {
        _ = try? core.send(
            RestoreSearchCatalog(language: locale.language.languageCode?.identifier, region: locale.region?.identifier))
    }

    // MARK: - Actions - Reading

    /// The providers of `kind`, in the order Settings lists them.
    func providers(of kind: SearchProviderKind) -> [SearchProvider] {
        providers.filter { $0.kind == kind }
    }

    /// Whether the palette offers `provider` to Tab.
    func isEnabled(_ provider: SearchProvider) -> Bool {
        guard let builtIn = provider.builtIn else { return true }
        return settings(builtIn)?.isEnabled ?? builtIn.isEnabledByDefault
    }

    /// How the device keeps the built-in `provider`.
    func settings(_ provider: BuiltInSearchProvider) -> SearchProviderSettings? {
        published?.catalog.builtIns.first { $0.provider == provider }
    }

    /// The value the person set for `option` of `provider`, or nil for its default.
    func value(of option: SearchProviderOption, for provider: BuiltInSearchProvider) -> String? {
        settings(provider)?.options.first { $0.option == option }?.value
    }

    /// The provider a person added with identity `id`, as they typed it.
    func custom(_ id: UUID) -> CustomSearchProvider? {
        published?.catalog.custom.first { $0.id == id }
    }

    /// The provider the device keeps by `name`, or nil.
    func provider(named name: String?) -> SearchProvider? {
        name.flatMap { name in providers.first { $0.name == name } }
    }

    /// The default a Space follows: the private one in a private window.
    func defaultProvider(isPrivate: Bool) -> SearchProvider? {
        isPrivate ? privateDefaultProvider : defaultProvider
    }

    /// What a Space with `browsing`, in a private window or not, searches
    /// with: the default while it follows it, else its own choice as this
    /// device keeps it or as the Space carries it.
    func provider(for browsing: BrowsingPreferences, isPrivate: Bool) -> SearchProvider? {
        if browsing.followsDefaultSearch { return defaultProvider(isPrivate: isPrivate) }
        if let id = browsing.selectedCustomEngineID {
            return providers.first { $0.customID == id }
                ?? browsing.customSearchProviders.first { $0.id == id }.map(SearchProvider.init(carried:))
        }
        return provider(named: browsing.selectedBuiltInEngine?.name) ?? defaultProvider(isPrivate: isPrivate)
    }

    /// Whether a Space with `browsing` suggests searches.
    func suggests(for browsing: BrowsingPreferences) -> Bool {
        browsing.followsDefaultSuggestions ? suggestionsEnabled : browsing.searchSuggestionsEnabled
    }

    // MARK: - Actions - Edits

    func setDefault(_ provider: SearchProvider) throws {
        try core.send(SetDefaultSearch(provider: provider.seed))
    }

    func setPrivateDefault(_ provider: SearchProvider) throws {
        try core.send(SetPrivateSearch(provider: provider.seed))
    }

    func setSuggestionsEnabled(_ enabled: Bool) {
        _ = try? core.send(SetSearchSuggestions(enabled: enabled))
    }

    func setEnabled(_ provider: BuiltInSearchProvider, _ enabled: Bool) {
        _ = try? core.send(SetSearchProviderEnabled(provider: provider, isEnabled: enabled))
    }

    /// Gives `provider` its own `shortcuts`, or its own built-in ones for nil.
    func setShortcuts(_ provider: BuiltInSearchProvider, _ shortcuts: [String]?) throws {
        try core.send(SetSearchShortcuts(provider: provider, shortcuts: shortcuts))
    }

    /// Sets `option` of `provider` to `value`, or back to its default for nil or blank.
    func setOption(_ option: SearchProviderOption, of provider: BuiltInSearchProvider, to value: String?) {
        _ = try? core.send(SetSearchOption(provider: provider, option: option, value: value))
    }

    /// Saves `provider` in place of the one of its identity, or after the others.
    func save(_ provider: CustomSearchProvider) throws {
        try core.send(SaveSearchProvider(provider: provider))
    }

    func remove(_ id: UUID) {
        _ = try? core.send(RemoveSearchProvider(id: id))
    }

    /// Returns every built-in to how it ships.
    func reset() {
        _ = try? core.send(ResetSearchProviders())
    }
}
