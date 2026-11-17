import AppKit
import Foundation

enum BrowserPlatformUserAgent {
    private static let safariBundleIdentifier = "com.apple.Safari"
    private static let safariVersionKey = "CFBundleShortVersionString"

    static let applicationName: String? = {
        guard
            let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: safariBundleIdentifier
            ),
            let safariBundle = Bundle(url: applicationURL)
        else {
            return nil
        }

        return applicationName(
            safariVersion: safariBundle.object(
                forInfoDictionaryKey: safariVersionKey
            ) as? String
        )
    }()

    static func applicationName(safariVersion: String?) -> String? {
        guard let safariVersion = normalizedSafariVersion(safariVersion) else {
            return nil
        }
        return "Version/\(safariVersion) Safari/605.1.15"
    }

    private static func normalizedSafariVersion(_ value: String?) -> String? {
        guard let value else { return nil }
        let version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
            components.allSatisfy({ component in
                !component.isEmpty && component.allSatisfy(\.isNumber)
            })
        else {
            return nil
        }
        return version
    }
}
