import Foundation

extension BrowserQuickWindowRequest {
    func retargeted(
        to url: URL,
        assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserQuickWindowRequest {
        BrowserQuickWindowRequest(
            id: id,
            url: url,
            spaceAssignment: assignment,
            targetWindowID: targetWindowID,
            sourcePresentation: sourcePresentation,
            openedPageID: openedPageID
        )
    }
}
