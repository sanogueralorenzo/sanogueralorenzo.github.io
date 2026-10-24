import Dispatch
import Foundation

/// Whether an archived state still describes the tab it was archived for.
///
/// A tab's URL is kept in step with its page, so an archived URL that no longer
/// matches means the tab was pointed somewhere else while it had no web view —
/// by the address bar, by an extension, or by a synchronized change from another
/// device. The tab's own URL wins in that case: restoring would quietly navigate
/// the user back to where they used to be.
extension SamePage {
    // MARK: - Actions - Answer

    static func restoresArchivedState(archivedURL: URL?, tabURL: URL) -> Bool {
        guard let archivedURL else { return false }
        if archivedURL == tabURL { return true }
        // Only the fragment may drift: WebKit restores the exact scroll and
        // in-page position anyway, so an anchor difference is not a mismatch.
        let match = try? CrestCore.answer(SamePage(first: archivedURL.absoluteString, second: tabURL.absoluteString))
        return match?.isSamePage == true
    }
}
