import Foundation

/// One presentation of setup: how the person arrived, and which showing of
/// the setup window or sheet this is.
struct BrowserOnboardingRequest: Codable, Hashable {
    // MARK: - Static Variables

    static var firstRun: Self { Self(entryPoint: .firstRun) }
    static var importBrowser: Self { Self(entryPoint: .importBrowser) }
    static var manualSetup: Self { Self(entryPoint: .manualSetup) }
    static var rerun: Self { Self(entryPoint: .rerun) }

    // MARK: - Variables

    let entryPoint: SetupEntry
    private let presentationID: UUID

    // MARK: - Initializers

    init(entryPoint: SetupEntry, presentationID: UUID = UUID()) {
        self.entryPoint = entryPoint
        self.presentationID = presentationID
    }
}
