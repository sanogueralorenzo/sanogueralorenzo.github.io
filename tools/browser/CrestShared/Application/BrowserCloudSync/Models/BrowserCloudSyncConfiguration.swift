struct BrowserCloudSyncConfiguration: Equatable, Sendable {
    static let defaultZoneName = "CrestPrivate"
    let containerIdentifier: String
    let zoneName: String

    init(containerIdentifier: String, zoneName: String = Self.defaultZoneName) {
        self.containerIdentifier = containerIdentifier
        self.zoneName = zoneName
    }

    /// Review devices share an explicit zone while retaining separate local profiles.
    /// Tests, previews and unnamed ephemeral launches can never connect to iCloud.
    func isolated(for environment: BrowserLaunchEnvironment) -> Self? {
        guard environment.explicitlyRequiresIsolation,
            environment.persistentIsolationID != nil,
            !environment.isXCTestRuntime, !environment.isSwiftUIPreviewRuntime,
            let identifier = environment.isolatedCloudSyncID
        else { return nil }
        return Self(containerIdentifier: containerIdentifier, zoneName: "CrestReview-" + identifier)
    }
}
