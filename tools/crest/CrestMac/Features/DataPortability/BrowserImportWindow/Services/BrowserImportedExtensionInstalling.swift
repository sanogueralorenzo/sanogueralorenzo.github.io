/// Installs the extensions an import brought once the import has made the
/// Spaces they go into, confirming each one with the person. Only an engine
/// that runs extensions supplies one, and setup offers no extensions without
/// it.
@MainActor
protocol BrowserImportedExtensionInstalling: AnyObject {
    func installImported(_ installs: [ImportExtensionInstall])
}
