import Foundation
import UIKit

/// Whether Crest is the device's default browser. The system answers about
/// once a year, so Crest keeps the last answer it had and goes by it while the
/// system declines to answer again. A web link another app opens in Crest
/// answers too: only the default browser receives those.
@MainActor
enum BrowserPlatformDefaultBrowserSystem {
    // MARK: - Static Variables

    static let requestStyle = BrowserDefaultBrowserRequestStyle.systemSettings

    private static let lastAnswerKey = "crest.default-browser.last-answer"

    /// The last answer the system or an opened link gave, nil before either.
    private static var lastAnswer: Bool? {
        get { UserDefaults.standard.object(forKey: lastAnswerKey) as? Bool }
        set { UserDefaults.standard.set(newValue, forKey: lastAnswerKey) }
    }

    // MARK: - Actions - Status

    static func checkStatus() throws -> Bool {
        do {
            let isDefault = try UIApplication.shared.isDefault(.webBrowser)
            lastAnswer = isDefault
            return isDefault
        } catch {
            guard isRateLimited(error), let lastAnswer else { throw error }
            return lastAnswer
        }
    }

    /// Notes a link another app opened in Crest, which only the default
    /// browser receives when it is a web address.
    static func noteOpenedLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        lastAnswer = true
    }

    /// What the person reads when the system declined to answer, or nil to
    /// show the error's own description.
    static func userFacingDescription(for error: any Error) -> String? {
        guard isRateLimited(error) else { return nil }

        if let retryDate = (error as NSError).userInfo[
            UIApplication.CategoryDefaultError.retryAvailableDateErrorKey
        ] as? Date {
            return
                "Apple limits default-browser checks. Try again after \(retryDate.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Apple limits how often Crest can check this status. Review it in Default Apps Settings."
    }

    /// Whether the system declined to answer because Crest asked too recently.
    private static func isRateLimited(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == UIApplication.CategoryDefaultError.errorDomain
            && error.code == UIApplication.CategoryDefaultError.rateLimited.rawValue
    }

    // MARK: - Actions - Choosing

    static func requestDefault() async throws {
        openSettings()
    }

    static func openSettings() {
        guard
            let url = URL(
                string: UIApplication.openDefaultApplicationsSettingsURLString
            )
        else { return }
        UIApplication.shared.open(url)
    }
}
