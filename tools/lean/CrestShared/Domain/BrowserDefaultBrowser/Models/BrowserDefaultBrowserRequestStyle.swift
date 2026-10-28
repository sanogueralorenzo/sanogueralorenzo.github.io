import Foundation

/// How a platform lets Crest ask to become the default browser, with the
/// button General settings offers for it.
struct BrowserDefaultBrowserRequestStyle: Equatable, Sendable {
    // MARK: - Static Variables

    /// The platform asks the person itself.
    static let direct = BrowserDefaultBrowserRequestStyle(
        name: "direct", buttonTitle: "Make Default", buttonIdentifier: "make-default-browser",
        waitsForRequest: true,
        request: { controller in
            Task { await controller.requestDefault() }
        })

    /// The person chooses in the system's settings.
    static let systemSettings = BrowserDefaultBrowserRequestStyle(
        name: "systemSettings", buttonTitle: "Open Settings…", buttonIdentifier: "open-default-apps-settings",
        waitsForRequest: false,
        request: { controller in
            controller.openSystemSettings()
        })

    // MARK: - Variables

    let name: String
    let buttonTitle: LocalizedStringResource
    let buttonIdentifier: String

    /// Whether the button waits while a request is working.
    let waitsForRequest: Bool

    /// What the button does.
    let request: @MainActor @Sendable (BrowserDefaultBrowserController) -> Void

    // MARK: - Initializers

    private init(
        name: String, buttonTitle: LocalizedStringResource, buttonIdentifier: String, waitsForRequest: Bool,
        request: @escaping @MainActor @Sendable (BrowserDefaultBrowserController) -> Void
    ) {
        self.name = name
        self.buttonTitle = buttonTitle
        self.buttonIdentifier = buttonIdentifier
        self.waitsForRequest = waitsForRequest
        self.request = request
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserDefaultBrowserRequestStyle, rhs: BrowserDefaultBrowserRequestStyle) -> Bool {
        lhs.name == rhs.name
    }
}
