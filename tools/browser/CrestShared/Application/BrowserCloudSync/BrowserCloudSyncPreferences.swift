/// Whether the person turned iCloud sync on, kept in this device's defaults.
@MainActor
protocol BrowserCloudSyncPreferences: AnyObject {
    func loadIsEnabled() -> Bool?
    func saveIsEnabled(_ isEnabled: Bool)
}
