import Foundation

/// An action offered by the update screen.
struct BrowserSoftwareUpdateAction: Hashable, Sendable {
    // MARK: - Static Variables

    static let installUpdate = Self(name: "installUpdate") { $0.installUpdate() }
    /// The screen opens the release's page itself.
    static let viewUpdateInformation = Self(name: "viewUpdateInformation")
    static let dismissExactUpdate = Self(name: "dismissExactUpdate") { updater in
        // Sparkle persists `.skip` against the exact appcast build. Its own
        // app-scoped store is authoritative, and a newer build is therefore
        // offered again without Crest maintaining a competing dismissal key.
        updater.skipUpdate()
    }
    static let cancelUpdate = Self(name: "cancelUpdate") { $0.cancelCurrentOperation() }
    static let installAndRelaunch = Self(name: "installAndRelaunch") { $0.installAndRelaunchNow() }
    static let retryUpdateInstallation = Self(name: "retryUpdateInstallation") {
        $0.retryApplicationTermination()
    }
    static let acknowledgeUpdateStatus = Self(name: "acknowledgeUpdateStatus") { $0.acknowledge() }

    // MARK: - Variables

    private let name: String
    private let performance: @MainActor @Sendable (BrowserSoftwareUpdateModel) -> Void

    // MARK: - Initializers

    private init(name: String, perform: @escaping @MainActor @Sendable (BrowserSoftwareUpdateModel) -> Void = { _ in })
    {
        self.name = name
        performance = perform
    }

    // MARK: - Actions - Performing

    @MainActor func perform(on updater: BrowserSoftwareUpdateModel) { performance(updater) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }

    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
