import Foundation

extension SetupImportReview {
    /// What the review brings, in one line: the selected tabs, then the
    /// passwords and the pinned tabs that move to a saved folder, where there
    /// are any.
    var summary: LocalizedStringResource {
        let tabs = max(includedTabCount, 0)
        let passwords = max(includedPasswordCount, 0)
        let overflowTabs = max(overflowTabIDs.count, 0)

        switch (passwords == 0, overflowTabs == 0) {
        case (true, true):
            return LocalizedStringResource(
                "\(tabs) tabs selected",
                comment: "Selected tab count in the browser-import review."
            )
        case (false, true):
            return LocalizedStringResource(
                "\(tabs) tabs selected · \(passwords) passwords",
                comment:
                    "Browser-import review summary. The first count is tabs; the second is passwords."
            )
        case (true, false):
            return LocalizedStringResource(
                "\(tabs) tabs selected · \(overflowTabs) pinned tabs move to a saved folder",
                comment:
                    "Browser-import review summary. The first count is selected tabs; the second is pinned tabs that must become saved tabs."
            )
        case (false, false):
            return LocalizedStringResource(
                "\(tabs) tabs selected · \(passwords) passwords · \(overflowTabs) pinned tabs move to a saved folder",
                comment:
                    "Browser-import review summary. Counts are selected tabs, passwords, then pinned tabs that must become saved tabs."
            )
        }
    }
}
