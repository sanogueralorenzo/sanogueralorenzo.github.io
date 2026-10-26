import SwiftUI
import Translation

struct BrowserTranslationHost: ViewModifier {
    @Bindable var translation: BrowserPageTranslation
    /// The page, not one engine's view. Its engine supplies the document
    /// whole-page translation rewrites; an engine that does not declare
    /// `translation` supplies none and the modifier stays inert rather than
    /// the shells having to know which engine they composed.
    let page: BrowserPlatformPage
    let isActive: Bool
    let isLoading: Bool
    let isReaderActive: Bool

    @State private var hostID = UUID()
    @Environment(\.scenePhase) private var scenePhase
    private var preferences: BrowserAppPreferenceStore { .shared }

    /// Asked for each time, so a page that moved to another engine hands over
    /// that engine's document.
    private var translationDocument: BrowserTranslationDocument? {
        page.pageEngine.registration.supports(.translation) ? page.translationDocument : nil
    }

    /// What detecting the page's language depends on; detection runs again
    /// whenever any of it changes.
    private struct Detection: Equatable {
        let documentRevision: Int
        let isActive: Bool
        let isLoading: Bool
        let isReaderActive: Bool
        let isInBackground: Bool
        let targetLanguage: String
        let translateAutomatically: Bool
        let excludedLanguages: [String]
    }

    private var detection: Detection {
        Detection(
            documentRevision: translation.documentRevision, isActive: isActive, isLoading: isLoading,
            isReaderActive: isReaderActive, isInBackground: scenePhase == .background,
            targetLanguage: preferences.translationLanguage,
            translateAutomatically: preferences.translateAutomatically,
            excludedLanguages: preferences.excludedTranslationLanguages)
    }

    func body(content: Content) -> some View {
        let configuration = translation.configuration
        return
            content
            .task(id: detection) {
                guard !Task.isCancelled, let document = translationDocument else { return }
                translation.updateTargetLanguage(preferences.translationLanguage)
                translation.setActive(
                    isActive && !isReaderActive && scenePhase != .background, in: document, hostID: hostID)
                guard !isLoading, !isReaderActive, isActive else { return }
                await translation.detect(
                    automatically: preferences.translateAutomatically,
                    excluding: preferences.excludedTranslationLanguages)
            }
            .translationTask(configuration) { session in
                await translation.run(using: session, configuration: configuration)
            }
            .onDisappear {
                if let document = translationDocument {
                    translation.setActive(false, in: document, hostID: hostID)
                }
            }
    }
}
