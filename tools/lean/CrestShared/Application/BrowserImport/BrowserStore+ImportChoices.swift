import Foundation

extension BrowserStore {
    /// Both preview and commit use the same explicit native choices. The
    /// session still validates and writes the import atomically.
    func reviewedImportIntent() throws -> ImportReviewedSpaces {
        core.drain()
        guard let flow = core.state.importFlow, flow.workspaceID == family.workspaceID, let review = flow.review else {
            throw NativeBrowserImport.Failure.notOpen
        }
        return ImportReviewedSpaces(
            workspaceID: family.workspaceID, windowID: windowID,
            reviews: review.spaces.map {
                ReviewedImportSpace.Seed(
                    source: $0.source.seed, included: $0.included, destinationID: $0.destinationID,
                    customization: $0.customization, includedTabIDs: $0.includedTabIDs, placements: $0.placements)
            })
    }
}
