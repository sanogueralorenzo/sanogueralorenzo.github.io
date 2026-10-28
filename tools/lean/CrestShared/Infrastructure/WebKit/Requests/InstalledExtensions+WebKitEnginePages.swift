import Foundation

extension InstalledExtensions {
    /// Only Chromium's binding is asked this.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        preconditionFailure("WebKit answers no InstalledExtensions.")
    }
}
