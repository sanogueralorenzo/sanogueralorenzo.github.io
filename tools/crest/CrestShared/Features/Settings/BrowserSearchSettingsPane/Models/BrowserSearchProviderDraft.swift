import Foundation

/// A search provider as its editor holds it before the core checks it: a
/// built-in, whose shortcuts alone the person may change, or one the person
/// adds or added, with every field as text, the shortcuts as one line, and
/// whether the person chose its color, which it otherwise takes from its icon.
struct BrowserSearchProviderDraft: Identifiable, Equatable {
    // MARK: - Static Variables

    /// A new provider with nothing filled in.
    static var adding: BrowserSearchProviderDraft {
        BrowserSearchProviderDraft(
            id: UUID(), builtIn: nil, isNew: true, kind: .engine, name: "", shortcuts: "", template: "",
            suggestions: "",
            color: .folderDefault, choseColor: false)
    }

    // MARK: - Variables

    let id: UUID
    /// The built-in being edited, or nil for a provider the person adds or added.
    let builtIn: BuiltInSearchProvider?
    let isNew: Bool
    var kind: SearchProviderKind
    var name: String
    var shortcuts: String
    var template: String
    var suggestions: String
    var color: BrandColor
    var choseColor: Bool

    /// The shortcuts as the person typed them, one by one.
    var shortcutList: [String] {
        shortcuts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The provider the person adds or added, as the core would check it.
    var custom: CustomSearchProvider {
        CustomSearchProvider(
            id: id, name: name, searchURLTemplate: template,
            suggestionURLTemplate: suggestions.isEmpty ? nil : suggestions,
            kind: kind, shortcuts: shortcutList, color: choseColor ? color : nil)
    }

    // MARK: - Initializers

    /// `provider` as its editor opens it, read from `catalog`.
    @MainActor
    init(_ provider: SearchProvider, catalog: BrowserSearchCatalog) {
        if let id = provider.customID, let custom = catalog.custom(id) {
            self.init(
                id: id, builtIn: nil, isNew: false, kind: custom.kind, name: custom.name,
                shortcuts: custom.shortcuts.joined(separator: ", "), template: custom.searchURLTemplate,
                suggestions: custom.suggestionURLTemplate ?? "", color: custom.color ?? provider.color,
                choseColor: custom.color != nil)
        } else {
            self.init(
                id: UUID(), builtIn: provider.builtIn, isNew: false, kind: provider.kind, name: provider.title,
                shortcuts: provider.shortcuts.joined(separator: ", "), template: provider.searchTemplate,
                suggestions: provider.suggestionTemplate ?? "", color: provider.color, choseColor: true)
        }
    }

    private init(
        id: UUID, builtIn: BuiltInSearchProvider?, isNew: Bool, kind: SearchProviderKind, name: String,
        shortcuts: String,
        template: String, suggestions: String, color: BrandColor, choseColor: Bool
    ) {
        self.id = id
        self.builtIn = builtIn
        self.isNew = isNew
        self.kind = kind
        self.name = name
        self.shortcuts = shortcuts
        self.template = template
        self.suggestions = suggestions
        self.color = color
        self.choseColor = choseColor
    }
}
