import Foundation

/// The words one shortcut row is found by: its title, section, search terms
/// and spoken shortcut.
struct BrowserShortcutSearchDocument: Equatable, Sendable {
    // MARK: - Variables

    let fields: [String]

    // MARK: - Actions - Searching

    /// Whether every term of `query` appears in the fields. A one-character
    /// term must match a whole word; an empty query matches everything.
    func matches(_ query: String) -> Bool {
        let terms =
            query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }

        let haystack = fields.joined(separator: " ").lowercased()
        let haystackTerms = haystack.split {
            !$0.isLetter && !$0.isNumber
        }
        return terms.allSatisfy { term in
            guard term.count == 1 else { return haystack.contains(term) }
            return haystackTerms.contains(term)
        }
    }
}
