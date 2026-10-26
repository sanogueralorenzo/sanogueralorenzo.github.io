import Foundation

struct BrowserCredentialDetailRequest: Equatable, Identifiable, Sendable {
    let descriptor: CredentialDescriptor
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let spaceName: String

    var id: BrowserCredentialDetailPresentationIdentity {
        BrowserCredentialDetailPresentationIdentity(
            credentialID: descriptor.id,
            spaceAssignment: spaceAssignment
        )
    }

    init(
        descriptor: CredentialDescriptor,
        spaceAssignment: BrowserSpaceRuntimeAssignment,
        spaceName: String
    ) {
        self.descriptor = descriptor
        self.spaceAssignment = spaceAssignment
        self.spaceName = spaceName
    }

    @MainActor
    init?(descriptor: CredentialDescriptor, space: SpaceModel) {
        guard descriptor.spaceID == space.id else { return nil }
        self.init(
            descriptor: descriptor,
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: space),
            spaceName: space.settings.name
        )
    }
}

struct BrowserCredentialDetailPresentationIdentity: Equatable, Hashable, Sendable {
    let credentialID: UUID
    let spaceAssignment: BrowserSpaceRuntimeAssignment
}
