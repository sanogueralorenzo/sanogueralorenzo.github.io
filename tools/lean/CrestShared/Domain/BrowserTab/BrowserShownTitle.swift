import Foundation

/// The rule every surface applies to a title a person or a page gave before
/// it shows it: surrounding whitespace goes, and a title with nothing left is
/// none, so a committed empty rename is how someone clears the name they
/// chose. The core applies the same rule to the titles it resolves.
enum BrowserShownTitle {
    // MARK: - Actions - Resolving

    /// `title` as a surface shows it, or nil when it shows none.
    static func resolve(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
