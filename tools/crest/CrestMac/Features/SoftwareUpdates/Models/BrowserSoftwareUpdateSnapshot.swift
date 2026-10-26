import Foundation

/// Facts the update screen needs to offer its buttons.
struct BrowserSoftwareUpdateSnapshot: Sendable {
    let informationURL: URL?
    let isInformationOnly: Bool
    let allowsInstallationRetry: Bool
}
