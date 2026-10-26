import Foundation

extension ExistingCredential {
    /// A saved password an import is compared against. Only a web form's
    /// password stands for an account a file imports.
    init(_ credential: BrowserCredential) {
        let descriptor = credential.descriptor
        self.init(
            id: descriptor.id, origin: descriptor.origin, username: descriptor.username,
            isWebForm: descriptor.scope == .webForm, updatedAt: descriptor.updatedAt.timeIntervalSince1970,
            lastUsedAt: descriptor.lastUsedAt?.timeIntervalSince1970, password: credential.password)
    }
}
