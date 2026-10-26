import AuthenticationServices
import Foundation

// MARK: - Types

enum BrowserSystemPasswordWriteThroughError: Error, Equatable {
    case unavailable
    case invalidScope
    case missingPresentationAnchor
}

@MainActor
enum BrowserSystemPasswordWriteThroughSystem {
    private static let buildManifestKey =
        "CrestSystemPasswordWriteThroughManagedCapability"

    /// This launch's platform facts for the core's write-through rule.
    static func facts(
        for launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> SystemPasswordWriteThrough {
        SystemPasswordWriteThrough(
            isMobilePlatform: true,
            supportsSystemPasswordSaving: supportsSystemPasswordSaving,
            hasManagedBrowserCapability: hasManagedBrowserCapability,
            isLaunchIsolated: launchEnvironment.requiresIsolation
        )
    }

    /// Offers the candidate to the system's Passwords app. `availability` is
    /// the core's answer for this launch; anything but `available` refuses.
    static func offer(
        candidate: BrowserCredentialSaveCandidate,
        title: String,
        anchor: ASPresentationAnchor?,
        availability: SystemPasswordWriteThroughAvailability
    ) async throws {
        guard availability == .available else {
            throw BrowserSystemPasswordWriteThroughError.unavailable
        }
        guard let anchor else {
            throw BrowserSystemPasswordWriteThroughError.missingPresentationAnchor
        }
        guard #available(iOS 26.2, *),
            let url = URL(string: candidate.origin.description),
            let scope = ASAutoFillURLScope(url: url)
        else {
            throw BrowserSystemPasswordWriteThroughError.invalidScope
        }

        try await ASCredentialDataManager().save(
            password: ASPasswordCredential(
                user: candidate.username,
                password: candidate.password
            ),
            for: scope,
            title: title,
            anchor: anchor
        )
    }

    private static var supportsSystemPasswordSaving: Bool {
        if #available(iOS 26.2, *) {
            true
        } else {
            false
        }
    }

    private static var hasManagedBrowserCapability: Bool {
        Bundle.main.object(forInfoDictionaryKey: buildManifestKey) as? Bool == true
    }
}
