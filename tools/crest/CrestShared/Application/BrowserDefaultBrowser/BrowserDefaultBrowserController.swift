import Foundation
import Observation

// MARK: - Types

/// What the system says about whether Crest opens links.
struct BrowserDefaultBrowserStatus: Hashable, Sendable {
    // MARK: - Types

    /// The color a status's symbol takes, which the view that draws it names.
    enum Tones: Sendable {
        case quiet
        case success
        case warning
    }

    // MARK: - Static Variables

    static let unknown = BrowserDefaultBrowserStatus(
        name: "unknown", title: "Not checked", symbol: "circle.dotted", tone: .quiet)
    static let isDefault = BrowserDefaultBrowserStatus(
        name: "isDefault", title: "Crest", symbol: "checkmark.circle.fill", tone: .success)
    static let notDefault = BrowserDefaultBrowserStatus(
        name: "notDefault", title: "Another browser", symbol: "circle", tone: .quiet)

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String
    let tone: Tones

    /// Why the system could not say, for a status it could not determine.
    let message: String?

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String, tone: Tones, message: String? = nil
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.tone = tone
        self.message = message
    }

    // MARK: - Actions - Building

    /// The system could not say, for the reason `message` gives.
    static func unavailable(_ message: String) -> BrowserDefaultBrowserStatus {
        BrowserDefaultBrowserStatus(
            name: "unavailable", title: "Unavailable", symbol: "exclamationmark.circle", tone: .warning,
            message: message)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserDefaultBrowserStatus, rhs: BrowserDefaultBrowserStatus) -> Bool {
        lhs.name == rhs.name && lhs.message == rhs.message
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(message)
    }
}

@Observable
@MainActor
final class BrowserDefaultBrowserController {
    typealias StatusCheck = @MainActor () throws -> Bool
    typealias DefaultRequest = @MainActor () async throws -> Void
    typealias SettingsOpener = @MainActor () -> Void

    private(set) var status = BrowserDefaultBrowserStatus.unknown
    private(set) var isWorking = false
    let requestStyle: BrowserDefaultBrowserRequestStyle

    @ObservationIgnored private let statusCheck: StatusCheck
    @ObservationIgnored private let defaultRequest: DefaultRequest
    @ObservationIgnored private let settingsOpener: SettingsOpener

    init(
        requestStyle: BrowserDefaultBrowserRequestStyle =
            BrowserPlatformDefaultBrowserSystem.requestStyle,
        statusCheck: @escaping StatusCheck =
            BrowserPlatformDefaultBrowserSystem.checkStatus,
        defaultRequest: @escaping DefaultRequest =
            BrowserPlatformDefaultBrowserSystem.requestDefault,
        settingsOpener: @escaping SettingsOpener =
            BrowserPlatformDefaultBrowserSystem.openSettings
    ) {
        self.requestStyle = requestStyle
        self.statusCheck = statusCheck
        self.defaultRequest = defaultRequest
        self.settingsOpener = settingsOpener
    }

    func refreshStatus() {
        do {
            status = try statusCheck() ? .isDefault : .notDefault
        } catch {
            status = .unavailable(Self.userFacingDescription(for: error))
        }
    }

    func requestDefault() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await defaultRequest()
            refreshStatus()
        } catch {
            status = .unavailable(Self.userFacingDescription(for: error))
        }
    }

    func openSystemSettings() {
        settingsOpener()
    }

    private static func userFacingDescription(for error: any Error) -> String {
        if let platformDescription =
            BrowserPlatformDefaultBrowserSystem.userFacingDescription(
                for: error
            )
        {
            return platformDescription
        }

        let message = error.localizedDescription.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return message.isEmpty
            ? "The system could not determine the default browser."
            : message
    }
}
