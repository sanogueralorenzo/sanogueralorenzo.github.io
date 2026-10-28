import AppKit
import Foundation

@MainActor
enum BrowserPlatformDefaultBrowserSystem {
    static let requestStyle = BrowserDefaultBrowserRequestStyle.direct

    static func checkStatus() throws -> Bool {
        let workspace = NSWorkspace.shared
        let applicationBundleID = Bundle.main.bundleIdentifier
        let destinationStrings = [
            "http://example.invalid/",
            "https://example.invalid/",
        ]
        let destinations = destinationStrings.compactMap(URL.init(string:))
        guard destinations.count == destinationStrings.count else {
            return false
        }

        return destinations.allSatisfy { destination in
            guard
                let handlerURL = workspace.urlForApplication(
                    toOpen: destination
                )
            else {
                return false
            }
            return Bundle(url: handlerURL)?.bundleIdentifier
                == applicationBundleID
        }
    }

    static func requestDefault() async throws {
        let applicationURL = Bundle.main.bundleURL
        try await NSWorkspace.shared.setDefaultApplication(
            at: applicationURL,
            toOpenURLsWithScheme: "http"
        )
        try await NSWorkspace.shared.setDefaultApplication(
            at: applicationURL,
            toOpenURLsWithScheme: "https"
        )
    }

    /// macOS has no answer of its own to add, so an error shows its own
    /// description.
    static func userFacingDescription(for error: any Error) -> String? {
        nil
    }

    static func openSettings() {
        NSWorkspace.shared.open(
            URL(
                fileURLWithPath:
                    "/System/Applications/System Settings.app"
            )
        )
    }
}
