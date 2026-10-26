import Foundation

#if os(macOS)
    /// Crest's process-wide preference for WebKit's macOS text checker.
    ///
    /// WebKit snapshots these app-domain defaults the first time its text checker
    /// is used. Configure them before creating a page so website editors receive
    /// literal input. Explicit text replacements remain user-controlled.
    enum BrowserMacWebTextAssistancePreference {
        private static let textReplacementKey = "WebAutomaticTextReplacementEnabled"
        private static let textReplacementMigrationKey = "crest.text-replacement.follows-system.v1"

        static let disabledSmartTextKeys = [
            "WebContinuousSpellCheckingEnabled",
            "WebAutomaticSpellingCorrectionEnabled",
            "WebGrammarCheckingEnabled",
            "WebSmartInsertDeleteEnabled",
            "WebSmartListsEnabled",
            BrowserAutomaticQuoteSubstitutionPreference.key,
            "WebAutomaticDashSubstitutionEnabled",
            "WebAutomaticLinkDetectionEnabled",
        ]

        static func configure(defaults: UserDefaults = .standard) {
            // Older Crest launches forced this app override off. Remove that
            // legacy value once so WebKit can consult NSSpellChecker's system
            // preference, then preserve either choice made in WebKit's menu.
            if !defaults.bool(forKey: textReplacementMigrationKey) {
                if defaults.object(forKey: textReplacementKey) != nil, !defaults.bool(forKey: textReplacementKey) {
                    defaults.removeObject(forKey: textReplacementKey)
                }
                defaults.set(true, forKey: textReplacementMigrationKey)
            }
            for key in disabledSmartTextKeys {
                defaults.set(false, forKey: key)
            }
        }
    }
#endif
