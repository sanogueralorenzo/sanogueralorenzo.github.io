import Foundation

/// An editor's inputs; the core owns the saved rule and origin normalization.
struct BrowserEngineRuleDraft: Identifiable {
    // MARK: - Variables

    let id = UUID()
    var previousOrigin: SiteOrigin?
    var website: String = ""
    var engine: EngineKind

    // MARK: - Initializers

    init(engine: EngineKind) { self.engine = engine }

    init(rule: SiteEngineRule) {
        previousOrigin = rule.origin
        website = rule.origin.displayName
        engine = rule.engine
    }
}
