import AVFoundation
import Foundation

/// The system's consent for one page: capture from the system's own
/// authorization, location and notifications through the services the page
/// uses for them.
@MainActor
final class BrowserSystemConsent: BrowserSystemConsenting {
    // MARK: - Types

    typealias Consent = @MainActor () async -> Bool

    // MARK: - Variables

    /// The service that answers for each capability the system gates
    /// besides capture. A capability without one is not gated.
    private let services: [SitePermission: Consent]

    // MARK: - Initializers

    /// A consent that asks `location` about location and `notifications`
    /// about notifications, each asking the person when the system has not
    /// decided.
    init(location: @escaping Consent, notifications: @escaping Consent) {
        services = [.location: location, .notifications: notifications]
    }

    // MARK: - Actions - Consent

    func consents(to permission: SitePermission) async -> Bool {
        if permission.isMedia { return await Self.captureConsents(to: permission) }
        return await services[permission]?() ?? true
    }

    /// Whether the system lets Crest use every device `permission` captures
    /// with, asking the person about each one it has not decided.
    private static func captureConsents(to permission: SitePermission) async -> Bool {
        let devices = permission.components.isEmpty ? [permission] : permission.components
        for device in devices {
            let type: AVMediaType = device == .camera ? .video : .audio
            switch AVCaptureDevice.authorizationStatus(for: type) {
            case .authorized:
                continue
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for: type) else { return false }
            default:
                return false
            }
        }
        return true
    }
}
