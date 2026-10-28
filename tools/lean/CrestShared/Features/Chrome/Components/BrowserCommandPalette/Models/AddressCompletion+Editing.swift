import Foundation

/// How accepting a completion edits the field: the suffix is typed after what
/// was typed when the accepted text only adds to it; otherwise the accepted
/// text, which names its scheme, replaces the field.
extension AddressCompletion {
    // MARK: - Variables

    var completedQuery: String { typed + suffix }

    var insertionText: String { accepted == completedQuery ? suffix : accepted }

    var insertionRange: NSRange {
        accepted == completedQuery
            ? NSRange(location: typed.utf16.count, length: 0)
            : NSRange(location: 0, length: typed.utf16.count)
    }
}
