import Foundation

extension BrowserStore {
    /// Sends one app-preference intent. Only the preference record changes, so
    /// every window keeps showing what it showed; a refusal changes nothing.
    @discardableResult
    func sendAppPreferences(_ intent: some Intent) -> Bool {
        family.send(intent, from: self, failure: "Core preference command failed")
    }
}
