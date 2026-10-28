import Foundation

extension PinnedExtensions {
    /// Only Chromium's binding is asked this.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        preconditionFailure("WebKit answers no PinnedExtensions.")
    }
}
