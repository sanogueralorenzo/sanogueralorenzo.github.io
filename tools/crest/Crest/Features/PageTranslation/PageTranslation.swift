import NaturalLanguage
import SwiftUI
@preconcurrency import Translation

/// Apple's translation service over Crest's existing isolated-document bridge.
struct PageTranslation: ViewModifier {
    let page: BrowserPage
    let store: BrowserStore
    @State private var configuration: TranslationSession.Configuration?
    @State private var requestedDocument = 0
    @State private var detectedLanguage: String?
    @State private var captureToken = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onChange(of: page.translationRequest) { request() }
            .task(id: page.documentRevision) {
                configuration = nil
                detectedLanguage = nil
                guard store.preferences.translatesAutomatically else { return }
                while page.isLoading, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(250)) }
                guard !Task.isCancelled, let sample = try? await document.sample() else { return }
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(sample.text)
                let language = recognizer.dominantLanguage?.rawValue ?? sample.declaredLanguage
                guard !language.isEmpty, language != store.preferences.translationLanguage,
                    !store.preferences.excludedLanguages.contains(language)
                else { return }
                detectedLanguage = language
                request()
            }
            .translationTask(configuration) { session in
                let revision = requestedDocument
                let token = captureToken
                do {
                    let capture = try await document.capture(token: token)
                    guard !capture.texts.isEmpty else { return }
                    let updates = try await Self.translate(capture.texts, using: session)
                    guard revision == page.documentRevision, !Task.isCancelled else { return }
                    _ = try await document.apply(updates, token: token)
                } catch {
                    guard revision == page.documentRevision, !Task.isCancelled else { return }
                    store.showNotice("Couldn’t translate this page: " + error.localizedDescription)
                }
            }
    }

    private nonisolated static func translate(
        _ texts: [String], using session: TranslationSession
    ) async throws -> [BrowserTranslationDocument.Update] {
        try await session.prepareTranslation()
        let requests = texts.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        let responses = try await session.translations(from: requests)
        return responses.compactMap { response in
            guard let id = response.clientIdentifier, let index = Int(id) else { return nil }
            return .init(index: index, text: response.targetText)
        }
    }

    private var document: BrowserTranslationDocument { BrowserTranslationDocument(webView: page.webView) }

    private func request() {
        requestedDocument = page.documentRevision
        captureToken = UUID().uuidString
        let next = TranslationSession.Configuration(
            source: detectedLanguage.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: store.preferences.translationLanguage))
        if configuration == next { configuration?.invalidate() } else { configuration = next }
    }
}
