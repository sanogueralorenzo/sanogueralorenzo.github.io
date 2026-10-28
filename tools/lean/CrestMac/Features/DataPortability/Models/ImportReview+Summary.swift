import Foundation

extension ImportReview {
    var summary: LocalizedStringResource {
        let tabs = max(includedTabCount, 0)
        let overflowTabs = max(overflowTabIDs.count, 0)
        if overflowTabs == 0 { return "\(tabs) tabs selected" }
        return "\(tabs) tabs selected · \(overflowTabs) pinned tabs move to a saved folder"
    }
}
