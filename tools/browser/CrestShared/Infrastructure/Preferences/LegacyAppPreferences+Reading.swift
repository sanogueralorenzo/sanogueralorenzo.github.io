import Foundation

/// The behavior preferences as the settings stored them in defaults before the
/// core owned them. They are read once, when a session first has no preference
/// record, and imported through the core's `ImportAppPreferences`, which reads
/// each stored spelling. The keys stay in place, so an older build still finds
/// its settings.
///
/// Each value is read from the same defaults its setting used: an isolated
/// launch never read the installed startup or Split View choices, and named
/// isolated profiles kept translation and saved-tab choices in their own suite.
/// A value that was never saved is nil.
extension LegacyAppPreferences {
    // MARK: - Static Variables

    static let startupKey = "crest.startup.behavior"
    static let automaticTranslationKey = "crest.translation.automaticallyTranslate"
    static let translationRulesKey = "crest.translation.languageRules"
    static let offersTranslationKey = "crest.translation.offerToTranslate"
    /// WebKit's own continuous-spelling default, which the setting wrote directly.
    static let spellCheckingKey = "WebContinuousSpellCheckingEnabled"
    static let pictureInPictureKey = "automaticallyEnterPictureInPicture"
    static let savedTabCloseKey = "crest.tabs.durable.closePolicy"
    static let savedTabFaviconKey = "crest.tabs.saved.returnToRootOnFaviconClick"
    static let splitFocusKey = "crest.split-view.focus-follows-mouse"

    /// Settings that were never saved, which import as the defaults.
    static let unsaved = LegacyAppPreferences(
        startupBehavior: nil, offersTranslation: nil, automaticallyTranslates: nil, translationRules: nil,
        checksSpelling: nil, automaticallyEntersPictureInPicture: nil, savedTabClosePolicy: nil,
        savedTabFaviconReturnsToSavedURL: nil, splitFocusFollowsMouse: nil)

    // MARK: - Actions - Reading

    static func read(
        for environment: BrowserLaunchEnvironment,
        standard: UserDefaults = .standard
    ) -> LegacyAppPreferences {
        let installed: UserDefaults? = environment.requiresIsolation ? nil : standard
        let profile: UserDefaults? =
            environment.requiresIsolation
            ? environment.persistentIsolationID.flatMap {
                UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: $0))
            }
            : standard
        return LegacyAppPreferences(
            startupBehavior: installed?.string(forKey: startupKey),
            offersTranslation: profile?.object(forKey: offersTranslationKey) as? Bool,
            automaticallyTranslates: profile?.object(forKey: automaticTranslationKey) as? Bool,
            translationRules: profile?.string(forKey: translationRulesKey),
            checksSpelling: standard.object(forKey: spellCheckingKey) as? Bool,
            automaticallyEntersPictureInPicture: standard.object(forKey: pictureInPictureKey) as? Bool,
            savedTabClosePolicy: profile?.string(forKey: savedTabCloseKey),
            savedTabFaviconReturnsToSavedURL: profile?.object(forKey: savedTabFaviconKey) as? Bool,
            splitFocusFollowsMouse: installed?.object(forKey: splitFocusKey) as? Bool
        )
    }
}
