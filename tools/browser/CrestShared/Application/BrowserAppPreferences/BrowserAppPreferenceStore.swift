import Foundation
import Observation

/// The core's app-wide behavior preferences, as the settings bind them.
///
/// Once bound to the persistent store, every value reads the core's accepted
/// `AppPreferences` and every edit is an intent that sets the whole record,
/// filled from the read model; an edit the core refuses leaves the current
/// value in place. Before binding, and in previews and tests that never bind,
/// the store holds its own record.
@Observable
@MainActor
final class BrowserAppPreferenceStore {
    // MARK: - Static Variables

    static let shared = BrowserAppPreferenceStore()

    // MARK: - Variables

    private var browser: BrowserStore?
    /// The unbound record, and the bound fallback, the documented defaults,
    /// while the session has no record because the legacy import could not
    /// commit.
    private var detached: AppPreferences

    var preferences: AppPreferences {
        browser?.workspaceModel?.appPreferences ?? detached
    }

    var startupBehavior: StartupBehavior {
        get { preferences.startup }
        set { set { $0.startup = newValue } }
    }

    var offersTranslation: Bool {
        get { preferences.offersTranslation }
        set { set { $0.offersTranslation = newValue } }
    }

    var automaticallyTranslates: Bool {
        get { preferences.automaticallyTranslates }
        set { set { $0.automaticallyTranslates = newValue } }
    }

    var checksSpelling: Bool {
        get { preferences.checksSpelling }
        set { set { $0.checksSpelling = newValue } }
    }

    var automaticallyEntersPictureInPicture: Bool {
        get { preferences.automaticallyEntersPictureInPicture }
        set {
            set { $0.automaticallyEntersPictureInPicture = newValue }
        }
    }

    var savedTabClosePolicy: SavedTabClosePolicy {
        get { preferences.savedTabClose }
        set { set { $0.savedTabClose = newValue } }
    }

    var returnsToSavedURLOnFaviconClick: Bool {
        get { preferences.savedTabFaviconReturnsToSavedURL }
        set {
            set { $0.savedTabFaviconReturnsToSavedURL = newValue }
        }
    }

    var splitFocusFollowsMouse: Bool {
        get { preferences.splitFocusFollowsMouse }
        set { set { $0.splitFocusFollowsMouse = newValue } }
    }

    var automaticallyShowsDeveloperToolbar: Bool {
        get { preferences.automaticallyShowsDeveloperToolbar }
        set { set { $0.automaticallyShowsDeveloperToolbar = newValue } }
    }

    /// How the command palette ranks and arranges what it offers.
    var palette: PalettePreferences {
        get { preferences.palette }
        set { set { $0.palette = newValue } }
    }

    // MARK: - Initializers

    init(preferences: AppPreferences = .default) {
        detached = preferences
    }

    // MARK: - Actions - Binding

    /// Binds the projection to the persistent store and, the first time a
    /// session has no record, imports the values the settings stored before
    /// the core owned them. Later launches find the record and import nothing.
    func bind(to browser: BrowserStore, legacy: LegacyAppPreferences) {
        detached = .default
        self.browser = browser
        guard browser.workspaceModel?.appPreferences == nil else { return }
        browser.sendAppPreferences(ImportAppPreferences(workspaceID: browser.family.workspaceID, legacy: legacy))
    }

    // MARK: - Actions - Translation

    /// Records a source language's choice through the core's alias rules. An
    /// unbound store has no core to apply them and keeps its rules.
    func setTranslationRule(sourceID: String, targetID: String, isEnabled: Bool) {
        guard let browser else { return }
        browser.sendAppPreferences(
            SetTranslationRule(
                workspaceID: browser.family.workspaceID, sourceLanguage: sourceID, targetLanguage: targetID,
                isEnabled: isEnabled))
    }

    // MARK: - Actions - Commands

    /// Applies `edit` to the unbound value, or sends the record it makes of
    /// the current one to the core.
    private func set(_ edit: (inout AppPreferences) -> Void) {
        guard let browser else {
            edit(&detached)
            return
        }
        var next = preferences
        edit(&next)
        browser.sendAppPreferences(SetAppPreferences(workspaceID: browser.family.workspaceID, preferences: next))
    }
}
