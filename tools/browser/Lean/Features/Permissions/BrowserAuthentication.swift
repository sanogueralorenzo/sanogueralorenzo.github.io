import AppKit
import Foundation

/// Website HTTP authentication stays in memory; there is no password-saving option.
@MainActor enum BrowserAuthentication {
    static func answer(_ challenge: URLAuthenticationChallenge, in window: NSWindow?) async -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        guard
            [
                NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM,
                NSURLAuthenticationMethodDefault,
            ].contains(method)
        else { return (.performDefaultHandling, nil) }
        guard challenge.previousFailureCount < 3, let window else { return (.cancelAuthenticationChallenge, nil) }
        let alert = NSAlert()
        alert.messageText = "Sign in to " + challenge.protectionSpace.host
        alert.informativeText = String((challenge.protectionSpace.realm ?? "").prefix(1000))
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 66))
        let username = NSTextField(frame: NSRect(x: 0, y: 36, width: 320, height: 24))
        username.placeholderString = "Username"
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        password.placeholderString = "Password"
        fields.addSubview(username)
        fields.addSubview(password)
        alert.accessoryView = fields
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        guard await BrowserDialogs.ask(alert, in: window) == .alertFirstButtonReturn else {
            return (.cancelAuthenticationChallenge, nil)
        }
        return (
            .useCredential,
            URLCredential(user: username.stringValue, password: password.stringValue, persistence: .none)
        )
    }
}
