import Foundation

extension SettleExtensionInstall {
    /// WebKit has no extensions, so the core never asks it to.
    @MainActor func perform(on binding: WebKitEngineBinding) {}
}
