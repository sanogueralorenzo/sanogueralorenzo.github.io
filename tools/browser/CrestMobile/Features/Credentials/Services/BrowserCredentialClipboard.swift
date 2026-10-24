import UIKit
import UniformTypeIdentifiers

@MainActor
enum BrowserCredentialClipboard {
    static func write(_ lease: BrowserCredentialSecretLease) -> Bool {
        guard let password = lease.password() else { return false }

        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: password]],
            options: [
                .localOnly: true,
                .expirationDate: lease.expiration,
            ]
        )
        return true
    }
}
