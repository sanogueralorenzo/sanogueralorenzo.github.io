import Foundation

extension ExportedCredential {
    /// A saved password as a Space's password file writes it, with the note
    /// naming how an HTTP authentication password is used.
    init(_ credential: BrowserCredential) {
        let descriptor = credential.descriptor
        self.init(
            id: descriptor.id, origin: descriptor.origin, username: descriptor.username,
            displayName: descriptor.displayName, password: credential.password,
            note: descriptor.scope.settingsLabel ?? "")
    }
}
