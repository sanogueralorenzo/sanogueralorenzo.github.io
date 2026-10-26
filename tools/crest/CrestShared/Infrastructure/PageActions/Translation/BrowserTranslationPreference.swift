import Foundation
import Translation

/// Translation language availability. The translation choices themselves are
/// core preferences; see `BrowserAppPreferenceStore`.
enum BrowserTranslationPreference {
    // MARK: - Types

    /// Every language Apple translates, and the ones its low-latency models
    /// cover. A pair outside the low-latency models uses Apple's default model.
    struct Languages: Sendable {
        /// Before Apple answers: no languages, and low latency for every pair.
        static let unloaded = Languages(all: [], lowLatencyIDs: [])

        let all: [Locale.Language]
        let lowLatencyIDs: Set<String>

        /// Whether Apple's low-latency models cover both languages. An empty
        /// source is the page's detected language, which they cover when they
        /// cover the target. Apple can answer an empty low-latency list while
        /// those models still translate, so an empty list keeps them for every
        /// pair.
        func usesLowLatency(from source: String, to target: String) -> Bool {
            lowLatencyIDs.isEmpty
                || ((source.isEmpty || lowLatencyIDs.contains(source)) && lowLatencyIDs.contains(target))
        }
    }

    // MARK: - Actions - Languages

    nonisolated static func languages() async -> Languages {
        let general = await LanguageAvailability().supportedLanguages
        guard #available(iOS 26.4, macOS 26.4, *) else { return Languages(all: general, lowLatencyIDs: []) }
        let lowLatency = await LanguageAvailability(preferredStrategy: .lowLatency).supportedLanguages
        let lowLatencyIDs = Set(lowLatency.map(\.minimalIdentifier))
        let generalIDs = Set(general.map(\.minimalIdentifier))
        return Languages(
            all: general + lowLatency.filter { !generalIDs.contains($0.minimalIdentifier) },
            lowLatencyIDs: lowLatencyIDs)
    }

    nonisolated static func languageAvailability(lowLatency: Bool) -> LanguageAvailability {
        if lowLatency, #available(iOS 26.4, macOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: .lowLatency)
        }
        return LanguageAvailability()
    }

    nonisolated static func preferredTarget(
        in available: [Locale.Language], preferred: Locale.Language
    ) -> Locale.Language {
        available.first { $0.minimalIdentifier == preferred.minimalIdentifier }
            ?? available.first { $0.languageCode == preferred.languageCode && $0.script == preferred.script }
            ?? preferred
    }
}
