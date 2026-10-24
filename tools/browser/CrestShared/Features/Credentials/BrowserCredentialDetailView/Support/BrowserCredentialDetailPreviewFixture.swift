import Foundation

@MainActor
enum BrowserCredentialDetailPreviewFixture {
    static let referenceDate = Date(timeIntervalSince1970: 1_000)
    static let spaceName = "Design"
    static let spaceID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
    )
    static let profileID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)
    )
    static let origin: CredentialOrigin = {
        guard
            let origin = CredentialOrigin(
                securityProtocol: "https",
                host: "developer.apple.com",
                port: 443
            )
        else {
            preconditionFailure("The credential-detail preview origin is invalid.")
        }
        return origin
    }()
    static let assignment = BrowserSpaceRuntimeAssignment(
        spaceID: spaceID,
        profileID: profileID
    )
    static let descriptor = CredentialDescriptor(
        id: UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)
        ),
        spaceID: spaceID,
        origin: origin,
        username: "developer@example.com",
        displayName: "Apple Developer",
        createdAt: referenceDate
    )
    static let request = BrowserCredentialDetailRequest(
        descriptor: descriptor,
        spaceAssignment: assignment,
        spaceName: spaceName
    )
    static let credential = BrowserCredential(
        descriptor: descriptor,
        password: "correct-horse-battery-staple"
    )

    static func makeModel() -> BrowserCredentialDetailModel {
        BrowserCredentialDetailModel(
            descriptor: descriptor,
            assignment: assignment,
            spaceName: spaceName,
            isAssignmentCurrent: { $0 == assignment },
            revealCredential: { _, _, _ in credential },
            writeClipboard: { _ in true },
            now: { referenceDate },
            sleep: { _ in throw CancellationError() }
        )
    }
}
