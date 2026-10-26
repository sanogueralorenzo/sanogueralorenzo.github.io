import Foundation

/// The device-local records an older release kept in defaults before the
/// core's device store held them. The composition reads them at every launch
/// and the core adopts them once; the keys stay in place, so an older build
/// still finds them.
///
/// They are read from the defaults the launch's core store belongs to: the
/// installed app's own, a named isolated launch's suite, or none for a launch
/// that keeps everything in memory.
struct BrowserLegacyDeviceDefaults: Equatable, Sendable {
    // MARK: - Static Variables

    static let sitePermissionsKey = "crest.site-permissions.v1"
    static let shortcutsKey = "crest.keyboard-shortcuts.v1"
    static let linkPreferencesKey = "crest.link-preferences.v1"
    static let manualSetupDraftKey = "BrowserManualSetupDraft"
    static let setupCompletedKey = "crest.onboarding.completed"

    // MARK: - Variables

    /// The saved site permission document, or nil when none was saved.
    var sitePermissions: Data?
    /// The saved shortcut choices, or nil when none were saved.
    var shortcuts: Data?
    /// The saved link preferences, or nil when none were saved.
    var linkPreferences: Data?
    /// The unfinished manual setup, or nil when none was saved.
    var manualSetupDraft: Data?
    /// Whether setup was completed on this device. A launch that keeps
    /// everything in memory, and so reads no defaults, counts as having
    /// completed it.
    var setupCompleted = true

    // MARK: - Actions - Reading

    static func read(
        for environment: BrowserLaunchEnvironment,
        standard: UserDefaults = .standard
    ) -> BrowserLegacyDeviceDefaults {
        let defaults: UserDefaults? =
            environment.requiresIsolation
            ? environment.persistentIsolationID.flatMap {
                UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: $0))
            }
            : standard
        return BrowserLegacyDeviceDefaults(
            sitePermissions: defaults?.data(forKey: sitePermissionsKey),
            shortcuts: defaults?.data(forKey: shortcutsKey),
            linkPreferences: defaults?.data(forKey: linkPreferencesKey),
            manualSetupDraft: defaults?.data(forKey: manualSetupDraftKey),
            setupCompleted: defaults?.bool(forKey: setupCompletedKey) ?? true)
    }
}
