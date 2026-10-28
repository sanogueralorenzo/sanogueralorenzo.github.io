import Foundation
@testable import Crest

extension CrestCore {
    /// Has every engine erase the profile of the Space `space` names, which
    /// keeps nothing on disk in a test, as the app's deleter does before the
    /// Space may go.
    func eraseProfile(of space: BrowserSpaceRuntimeAssignment) async throws {
        guard await deleteData(DeleteProfileData(requestID: UUID(), profileID: space.profileID, ephemeral: true))
        else { throw BrowserSpaceDeletionError.dataNotErased }
    }
}
