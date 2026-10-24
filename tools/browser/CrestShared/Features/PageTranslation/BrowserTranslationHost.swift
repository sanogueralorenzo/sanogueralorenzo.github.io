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
    private var preferences: AppPreferences { BrowserAppPreferenceStore.shared.preferences }
    private var automaticallyTranslates: Bool { preferences.automaticallyTranslates }
    private var offersTranslation: Bool { preferences.offersTranslation }
    private var languageRules: [TranslationRule] { preferences.translationRules }

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
        let automaticallyTranslates: Bool
        let languageRules: [TranslationRule]
    }

    private var detection: Detection {
        Detection(
            documentRevision: translation.documentRevision, isActive: isActive, isLoading: isLoading,
            isReaderActive: isReaderActive, isInBackground: scenePhase == .background,
            automaticallyTranslates: automaticallyTranslates, languageRules: languageRules)
    }

    func body(content: Content) -> some View {
        let configuration = translation.configuration
        return
            content
            .task(id: detection) {
                guard !Task.isCancelled, let document = translationDocument else { return }
                translation.updatePreferences(
                    automaticallyTranslates: automaticallyTranslates, offersTranslation: offersTranslation,
                    languageRules: languageRules)
                translation.setActive(
                    isActive && !isReaderActive && scenePhase != .background, in: document, hostID: hostID)
                guard !isLoading, !isReaderActive, isActive else { return }
                await translation.detect()
                await translation.automaticallyTranslateIfAvailable(enabled: automaticallyTranslates)
            }
            .task(id: "\(translation.languageStatusID)-\(translation.isOffered)-\(isActive)-\(scenePhase)") {
                guard isActive, translation.isOffered, scenePhase == .active else { return }
                await translation.refreshInstalledLanguages(force: true)
            }
            .translationTask(configuration) { session in
                await translation.run(using: session, configuration: configuration)
            }
            .onChange(of: offersTranslation) {
                translation.updatePreferences(
                    automaticallyTranslates: automaticallyTranslates, offersTranslation: offersTranslation,
                    languageRules: languageRules)
            }
            .onDisappear {
                if let document = translationDocument {
                    translation.setActive(false, in: document, hostID: hostID)
                }
            }
            .sheet(isPresented: $translation.showsInformation) {
                BrowserTranslationInformation(translation: translation)
            }
    }
}

private struct BrowserTranslationInformation: View {
    let translation: BrowserPageTranslation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !translation.status.isEmpty {
                    Section("Status") { Text(translation.status) }
                }
                Section("On-device Translation") {
                    Text(
                        "Apple translates page text on this device. Languages may need to download first; Apple asks before downloading. Downloaded languages are shared with other apps and remain available after Private Browsing ends."
                    )
                    Text(
                        "Automatically Translate is off by default. Choose which languages to translate and their destination languages in Settings → General → Page Translation. Only enabled language mappings with downloaded languages translate automatically. Automatic translation never opens a translation bar or asks to download languages. Open the translation controls to check status or download missing languages. Turn off Offer to Translate to stop automatic offers. Show Original keeps that page in its original language until you navigate or reload."
                    )
                    #if os(iOS)
                        Text(
                            "Tap the address bar’s translation button for options, or touch and hold it to translate immediately."
                        )
                    #endif
                }
                Section("Download Languages") {
                    Text(
                        "Languages confirmed as downloaded appear first. Other choices may need a download; choose a language and tap Translate to let Apple prepare it."
                    )
                    #if os(macOS)
                        Text(
                            "You can also manage languages in System Settings → General → Language & Region → Translation Languages."
                        )
                    #else
                        Text(
                            "You can also download languages in Apple’s Translate app, or manage them in Settings → Apps → Translate → Downloaded Languages."
                        )
                    #endif
                }
                Section("Page Coverage") {
                    Text(
                        "Crest translates page text in place, including headings, links, labels, and buttons. Editable fields, code, embedded pages, and text in images are left unchanged. Translated text may take more space."
                    )
                    Text(
                        "Use Translate Page Again after a page loads new content. Show Original restores text changed by Crest while preserving later website changes and your edits."
                    )
                }
            }
            .navigationTitle("Page Translation")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
            .frame(width: 460, height: 440)
        #else
            .presentationDetents([.medium, .large])
        #endif
    }
}
