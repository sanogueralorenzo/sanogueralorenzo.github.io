import Foundation

/// Secure-origin rules answered by the portable core: whether a site may use
/// location or post hosted web notifications at all.
extension SecureOriginCheck {
    // MARK: - Variables

    /// Whether the origin is secure enough for the capability that asks. An
    /// unavailable core refuses.
    var isAllowed: Bool {
        (try? CrestCore.answer(self))?.allowed ?? false
    }
}
