import Foundation

@MainActor
final class BrowserCredentialSensitiveAccess {
    private let browser: BrowserStore
    private let authenticator: any BrowserDeviceAuthenticating

    init(
        browser: BrowserStore,
        authenticator: any BrowserDeviceAuthenticating =
            SystemBrowserDeviceAuthenticator()
    ) {
        self.browser = browser
        self.authenticator = authenticator
    }

    func revealCredential(
        id: UUID,
        in spaceID: UUID,
        reason: String = String(localized: "Authenticate to view this Crest password.")
    ) async throws -> BrowserCredential {
        guard try await authenticator.authenticate(reason: reason) else {
            throw BrowserCredentialSensitiveAccessError.authenticationDenied
        }
        guard let credential = try await browser.credential(id: id, in: spaceID),
            credential.descriptor.id == id,
            credential.descriptor.spaceID == spaceID
        else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        return credential
    }

    func revealCredential(
        id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        reason: String = String(localized: "Authenticate to view this Crest password.")
    ) async throws -> BrowserCredential {
        guard browser.spaceModel(matching: assignment) != nil else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        guard try await authenticator.authenticate(reason: reason) else {
            throw BrowserCredentialSensitiveAccessError.authenticationDenied
        }
        guard browser.spaceModel(matching: assignment) != nil else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        guard
            let credential = try await browser.credential(
                id: id,
                in: assignment.spaceID
            ), browser.spaceModel(matching: assignment) != nil,
            credential.descriptor.id == id,
            credential.descriptor.spaceID == assignment.spaceID
        else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        return credential
    }

    /// Authenticates, reads every password the Space keeps, and has the core
    /// write the Space's password file from them.
    func exportCredentials(in spaceID: UUID) async throws -> CredentialExportFile {
        guard let space = browser.spaceModel(spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        let spaceName = space.settings.name
        let reason = String(localized: "Authenticate to export passwords from \(spaceName).")
        guard try await authenticator.authenticate(reason: reason) else {
            throw BrowserCredentialSensitiveAccessError.authenticationDenied
        }

        let descriptors = try await browser.savedCredentialDescriptors(in: spaceID)
        var credentials: [ExportedCredential] = []
        credentials.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            guard
                let credential = try await browser.credential(
                    id: descriptor.id,
                    in: spaceID
                ), credential.descriptor.id == descriptor.id,
                credential.descriptor.spaceID == spaceID
            else {
                throw BrowserCredentialSensitiveAccessError.malformedCredentialInventory
            }
            credentials.append(ExportedCredential(credential))
        }
        return try browser.core.query(
            CredentialExport(credentials: credentials, spaceName: spaceName, fallbackName: String(localized: "Space")))
    }

    func credentialInventory(
        matching assignment: BrowserSpaceRuntimeAssignment,
        reason: String
    ) async throws -> [BrowserCredential] {
        guard browser.spaceModel(matching: assignment) != nil else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        guard try await authenticator.authenticate(reason: reason) else {
            throw BrowserCredentialSensitiveAccessError.authenticationDenied
        }
        guard browser.spaceModel(matching: assignment) != nil else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        let credentials = try await browser.credentialInventory(
            in: assignment.spaceID
        )
        guard
            browser.spaceModel(matching: assignment) != nil,
            credentials.allSatisfy({
                $0.descriptor.spaceID == assignment.spaceID
            })
        else {
            throw BrowserCredentialSensitiveAccessError.malformedCredentialInventory
        }
        return credentials
    }
}
