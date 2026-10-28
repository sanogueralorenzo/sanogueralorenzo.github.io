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
    /// The unbound record and the defaults used until a preference is saved.
    private var detached: AppPreferences

    var preferences: AppPreferences {
        browser?.workspaceModel?.appPreferences ?? detached
    }

    var searchProvider: SearchProvider {
        get { preferences.searchProvider }
        set { set { $0.searchProvider = newValue } }
    }

    var searchSuggestionsEnabled: Bool {
        get { preferences.searchSuggestionsEnabled }
        set { set { $0.searchSuggestionsEnabled = newValue } }
    }

    var translationLanguage: String {
        get { preferences.translationLanguage }
        set { set { $0.translationLanguage = newValue } }
    }

    var translateAutomatically: Bool {
        get { preferences.translateAutomatically }
        set { set { $0.translateAutomatically = newValue } }
    }

    var excludedTranslationLanguages: [String] {
        get { preferences.excludedTranslationLanguages }
        set { set { $0.excludedTranslationLanguages = newValue } }
    }

    // MARK: - Initializers

    init(preferences: AppPreferences = .default) {
        detached = preferences
    }

    // MARK: - Actions - Binding

    /// Reads the persistent workspace's accepted preferences from now on.
    func bind(to browser: BrowserStore) {
        detached = .default
        self.browser = browser
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
