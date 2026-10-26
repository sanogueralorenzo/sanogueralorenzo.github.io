import Foundation

#if os(macOS)
    /// WebKit reads its continuous-spelling default once per process, before the
    /// first page, and its own Spelling menu writes the same default. The core owns
    /// the choice; this keeps the engine's copy in step with it.
    extension BrowserAppPreferenceStore {
        /// Runs at launch, before any page exists. Settings writes the engine's copy
        /// whenever the choice changes, so a difference here is a choice WebKit's
        /// Spelling menu saved since the last launch, and the core records it.
        func reconcileWebKitSpellChecking(defaults: UserDefaults = .standard) {
            guard let engine = defaults.object(forKey: BrowserMacWebTextAssistancePreference.spellCheckingKey) as? Bool
            else {
                if checksSpelling { defaults.set(true, forKey: BrowserMacWebTextAssistancePreference.spellCheckingKey) }
                return
            }
            if engine != checksSpelling { checksSpelling = engine }
        }

        /// The Settings toggle: the core records the choice, and WebKit reads it
        /// the next time Crest opens.
        func setChecksSpellingForWebKit(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
            checksSpelling = isEnabled
            defaults.set(checksSpelling, forKey: BrowserMacWebTextAssistancePreference.spellCheckingKey)
        }
    }
#endif
