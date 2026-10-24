import Foundation

extension Array where Element == TranslationRule {
    // MARK: - Actions - Deciding

    /// What the core decides for pages in `sourceID` under these rules: the
    /// rule that applies and the language it translates to. Rules the core
    /// refuses never translate, and a core that cannot answer decides nothing.
    func decision(for sourceID: String) -> TranslationDecision? {
        try? CrestCore.answer(TranslationChoice(rules: self, sourceLanguage: sourceID))
    }
}
