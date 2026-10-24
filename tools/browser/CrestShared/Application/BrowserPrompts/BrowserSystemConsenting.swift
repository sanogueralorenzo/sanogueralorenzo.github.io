import Foundation

/// The system's consent to Crest giving a site a capability the system gates
/// for the whole app: the camera, the microphone, location and notifications.
/// A page asks it before it sends the person's Allow to the core, so an Allow
/// the system refuses saves nothing.
@MainActor
protocol BrowserSystemConsenting: AnyObject {
    /// Whether the system lets Crest give a site `permission`, asking the
    /// person when the system has not decided. A permission the system does
    /// not gate answers true.
    func consents(to permission: SitePermission) async -> Bool
}
