import Foundation
import Observation

@Observable
@MainActor
final class BrowserSpaceSettingsPresentationState {
    private(set) var request: any BrowserSettingsRequest = BrowserSettingsSpaceRequest(tab: .appearance)
    private(set) var requestedAssignment: BrowserSpaceRuntimeAssignment?
    /// The search the request carries over from the Settings tab it came from.
    private(set) var searchText: String?
    private(set) var revision = 0

    var requestedSpaceID: UUID? { requestedAssignment?.spaceID }

    func present(assignment: BrowserSpaceRuntimeAssignment) {
        present(BrowserSettingsSpaceRequest(tab: .appearance), assignment: assignment)
    }

    /// Presents `destination`. A destination whose subject belongs to one
    /// Space opens that Space's page.
    func present(
        _ destination: BrowserSettingsDestination,
        assignment: BrowserSpaceRuntimeAssignment
    ) {
        let request: any BrowserSettingsRequest =
            BrowserSpaceSettingsTab.holding(destination).map { BrowserSettingsSpaceRequest(tab: $0) }
            ?? BrowserSettingsDestinationRequest(destination: destination)
        present(request, assignment: assignment)
    }

    func present(
        _ request: any BrowserSettingsRequest,
        assignment: BrowserSpaceRuntimeAssignment,
        searchText: String? = nil
    ) {
        self.request = request
        requestedAssignment = assignment
        self.searchText = searchText
        revision &+= 1
    }

    func requestedSpaceID(in browser: BrowserStore) -> UUID? {
        guard let requestedAssignment else { return nil }
        return browser.spaceModel(matching: requestedAssignment)?.id
    }
}
