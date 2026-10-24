import Foundation

extension ExternalLocalDocument {
    // MARK: - Actions - Answer

    /// Whether Crest opens this URL as a local document. Only document-open
    /// routes ask; a web link never reaches a local path through this. An
    /// unanswered question refuses the document.
    static func accepts(_ url: URL) -> Bool {
        let facts = LocalDocumentFacts(
            isFile: url.isFileURL, hasUser: url.user() != nil, hasPath: !url.path().isEmpty,
            host: url.host(percentEncoded: false).nonEmpty)
        return (try? CrestCore.answer(ExternalLocalDocument(facts: facts)))?.accepted ?? false
    }
}
