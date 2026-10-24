struct BrowserPasswordSettingsLayout: Equatable {
    let showsCredentialPreferences: Bool
    let showsSavedPasswords: Bool
    let showsExportAction: Bool
    let showsManageAction: Bool
    let supportsCredentialFileImport: Bool
    /// What the shell's exporter opens, named the way that shell's reader knows it:
    /// the desktop gets a save panel, touch gets the Files picker. The warning before
    /// a plaintext export names it, so the noun travels with the layout rather than
    /// with a platform check inside the pane.
    let exportDestinationName: String

    static let macOSPage = BrowserPasswordSettingsLayout(
        showsCredentialPreferences: false,
        showsSavedPasswords: true,
        showsExportAction: true,
        showsManageAction: false,
        supportsCredentialFileImport: true,
        exportDestinationName: "save panel"
    )

    /// One Space's Passwords page in desktop Settings, with its iCloud
    /// Keychain switch beside the list.
    static let macOSSpacePage = BrowserPasswordSettingsLayout(
        showsCredentialPreferences: true,
        showsSavedPasswords: true,
        showsExportAction: true,
        showsManageAction: false,
        supportsCredentialFileImport: true,
        exportDestinationName: "save panel"
    )

    static let mobilePage = BrowserPasswordSettingsLayout(
        showsCredentialPreferences: true,
        showsSavedPasswords: false,
        showsExportAction: false,
        showsManageAction: true,
        supportsCredentialFileImport: false,
        exportDestinationName: "Files picker"
    )

    /// The sheet touch keeps the manager in.
    ///
    /// It carries the Space's credential preferences as well as the list because the
    /// sidebar opens this sheet directly — a reader who never walks through Settings
    /// still has to be able to reach the iCloud Keychain switch.
    static let mobileSheet = BrowserPasswordSettingsLayout(
        showsCredentialPreferences: true,
        showsSavedPasswords: true,
        showsExportAction: true,
        showsManageAction: false,
        supportsCredentialFileImport: true,
        exportDestinationName: "Files picker"
    )
}
