import Foundation
import NaturalLanguage
import Observation
@preconcurrency import Translation

/// One live document owns its offer, model work, and restoration token. Nothing
/// here is persisted or shared between pages, Spaces, profiles, or private sessions.
@Observable @MainActor
final class BrowserPageTranslation {
    private(set) var sourceID = ""
    private(set) var targetID = AppPreferences.default.translationLanguage
    private var preferredTargetID = AppPreferences.default.translationLanguage
    @ObservationIgnored private var supportedLanguages = BrowserTranslationPreference.Languages.unloaded
    @ObservationIgnored private var languageLoadTask: Task<BrowserTranslationPreference.Languages, Never>?

    private(set) var configuration: TranslationSession.Configuration?
    private(set) var documentRevision = 0
    private(set) var isOffered = false
    private(set) var isWorking = false
    private(set) var isTranslated = false
    private(set) var status = ""

    @ObservationIgnored private var document: BrowserTranslationDocument?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var activeHostID: UUID?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var session: TranslationSession?
    @ObservationIgnored private var hasDetected = false
    @ObservationIgnored private var hasRequestedTranslation = false
    @ObservationIgnored private var lastConfiguration: TranslationSession.Configuration?
    @ObservationIgnored private var restorationTask: Task<Void, Error>?

    var targetName: String {
        Locale.current.localizedString(forIdentifier: targetID) ?? targetID
    }

    /// Apple's low-latency models where they cover the pair, and Apple's
    /// default model for a language they leave out, such as Swedish.
    private func usesLowLatency(from source: String, to target: String) -> Bool {
        supportedLanguages.usesLowLatency(from: source, to: target)
    }

    private func availability(from source: String, to target: String) -> LanguageAvailability {
        BrowserTranslationPreference.languageAvailability(lowLatency: usesLowLatency(from: source, to: target))
    }

    /// Whole-page translation rewrites the live DOM of `document`, the page's
    /// main document on whichever engine shows it.
    func setActive(_ active: Bool, in document: BrowserTranslationDocument, hostID: UUID? = nil) {
        // Reparenting a live page can mount its next host before the previous
        // host disappears. Only the current host may end that presentation.
        if !active, let hostID, activeHostID != hostID { return }
        activeHostID = active ? hostID : nil
        self.document = document
        isActive = active
        if !active { cancel() }
    }

    /// Detects the page's language once it settles. The page's host cancels
    /// detection when the page starts loading again and runs it anew.
    func detect(automatically: Bool = false, excluding excludedLanguages: [String] = []) async {
        guard isActive, !isWorking, !isTranslated, let document else { return }
        let revision = documentRevision
        do {
            if !hasDetected {
                for attempt in 0..<3 {
                    try await Task.sleep(for: .milliseconds(attempt == 0 ? 1500 : 1000))
                    guard isActive, revision == documentRevision, !isWorking else { return }
                    let sample = try await document.sample()
                    let detected = await Task.detached(priority: .utility) { Self.detectedLanguage(in: sample) }.value
                    try Task.checkCancellation()
                    guard isActive, revision == documentRevision, !isWorking else { return }
                    guard let detected else { continue }
                    sourceID = detected
                    break
                }
                hasDetected = true
            }
            guard !sourceID.isEmpty else { return }
            await loadLanguages()
            try Task.checkCancellation()
            guard isActive, revision == documentRevision, !isWorking else { return }
            let target = preferredTargetID
            guard !Self.sameLanguage(sourceID, target) else {
                isOffered = false
                return
            }
            let availability = await availability(from: sourceID, to: target).status(
                from: .init(identifier: sourceID), to: .init(identifier: target))
            try Task.checkCancellation()
            guard isActive, revision == documentRevision, !isWorking else { return }
            isOffered = availability != .unsupported
            if automatically, isOffered, !hasRequestedTranslation,
                !excludedLanguages.contains(where: {
                    Locale.Language(identifier: sourceID).languageCode == Locale.Language(identifier: $0).languageCode
                })
            {
                start()
            }
        } catch {
            // Detection never interrupts navigation. Only an enabled, eligible
            // automatic translation or a manual action requests model work.
        }
    }

    private static func sameLanguage(_ left: String, _ right: String) -> Bool {
        let a = Locale.Language(identifier: Locale.Language(identifier: left).maximalIdentifier)
        let b = Locale.Language(identifier: Locale.Language(identifier: right).maximalIdentifier)
        return a.languageCode == b.languageCode && a.script == b.script
    }

    nonisolated static func detectedLanguage(in sample: BrowserTranslationDocument.Sample) -> String? {
        guard sample.text.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 8 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample.text)
        let dominant = recognizer.dominantLanguage
        let confidence = dominant.map { recognizer.languageHypotheses(withMaximum: 1)[$0, default: 0] } ?? 0
        if sample.text.count >= 80, confidence >= 0.8 { return dominant?.rawValue }
        // Search pages and other mixed-language interfaces can have a weak
        // statistical result while explicitly declaring the document language.
        let declared = Locale.Language(identifier: sample.declaredLanguage)
        if !sample.declaredLanguage.isEmpty, let code = declared.languageCode?.identifier, code != "und" {
            return declared.minimalIdentifier
        }
        return sample.text.count >= 20 && confidence >= 0.6 ? dominant?.rawValue : nil
    }

    private func loadLanguages() async {
        guard supportedLanguages.all.isEmpty else { return }
        let load = languageLoadTask ?? Task { await BrowserTranslationPreference.languages() }
        languageLoadTask = load
        supportedLanguages = await load.value
        languageLoadTask = nil
    }

    func updateTargetLanguage(_ identifier: String) {
        guard preferredTargetID != identifier else { return }
        preferredTargetID = identifier
        hasDetected = false
        isOffered = false
    }

    var actionTitle: String {
        if isWorking { return String(localized: "Cancel Translation") }
        return isTranslated ? String(localized: "Show Original") : String(localized: "Translate Page")
    }

    func performAction() {
        if isWorking { cancel() } else if isTranslated { showOriginal() } else { start() }
    }

    func start() {
        guard isActive, !isWorking else { return }
        hasRequestedTranslation = true
        targetID = preferredTargetID
        isOffered = true
        #if targetEnvironment(simulator)
            status = String(
                localized: "Apple Translation requires a physical device. It is not available in Simulator.")
        #else
            isWorking = true
            status = String(localized: "Preparing translation…")
            var next = lastConfiguration ?? .init()
            next.source = nil
            next.target = .init(identifier: targetID)
            if #available(iOS 26.4, macOS 26.4, *) {
                next.preferredStrategy =
                    !supportedLanguages.all.isEmpty && usesLowLatency(from: sourceID, to: targetID)
                    ? .lowLatency : .highFidelity
            }
            next.invalidate()
            lastConfiguration = next
            configuration = next
        #endif
    }

    func run(using session: TranslationSession, configuration expected: TranslationSession.Configuration?) async {
        guard expected != nil,
            expected == configuration, isActive, isWorking, let document
        else { return }
        self.session = session
        let revision = documentRevision
        let operation = UUID().uuidString
        token = operation
        defer {
            if token == operation {
                isWorking = false
                configuration = nil
                self.session = nil
            }
        }
        do {
            let capture = try await document.capture(token: operation)
            try validate(operation, revision: revision)
            isTranslated = false
            guard !capture.texts.isEmpty else {
                status = String(
                    localized:
                        "No supported page text was found. Editable fields, embedded pages, and images are excluded.")
                return
            }
            // Apple identifies the text's language and handles any required
            // model downloads for manual or enabled automatic translation.
            var applied = 0
            var completed = 0
            try await Self.translate(capture.texts, using: session) { updates in
                try self.validate(operation, revision: revision)
                applied += try await document.apply(updates, token: operation)
                try self.validate(operation, revision: revision)
                completed += updates.count
                self.isTranslated = applied > 0
                self.status = String(localized: "Translating… \(completed) of \(capture.texts.count)")
            }
            if capture.isLimited || applied < capture.texts.count {
                status = String(
                    localized: "Translated available text. Some content was too large or changed during translation.")
            } else {
                status = String(localized: "Translated to \(targetName)")
            }
        } catch {
            guard token == operation, revision == documentRevision else { return }
            try? await document.restore(token: operation)
            guard token == operation, revision == documentRevision else { return }
            isTranslated = false
            status =
                error is CancellationError
                ? String(localized: "Translation cancelled. Original text restored.")
                : String(localized: "Translation could not finish. \(error.localizedDescription)")
        }
    }

    // Build requests and consume responses away from the UI executor. Repeated
    // text is translated once, and the first result reaches the page immediately.
    private nonisolated static func translate(
        _ texts: [String], using session: TranslationSession,
        receive: @MainActor @Sendable ([BrowserTranslationDocument.Update]) async throws -> Void
    ) async throws {
        let indices = Dictionary(grouping: texts.indices, by: { texts[$0] })
        var seen: Set<String> = []
        let requests = texts.enumerated().compactMap { index, text -> TranslationSession.Request? in
            guard seen.insert(text).inserted else { return nil }
            return TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        var pending: [BrowserTranslationDocument.Update] = []
        var lastDelivery: ContinuousClock.Instant?
        for try await response in session.translate(batch: requests) {
            try Task.checkCancellation()
            guard let identifier = response.clientIdentifier, let index = Int(identifier), texts.indices.contains(index)
            else { continue }
            pending += (indices[texts[index]] ?? []).map { .init(index: $0, text: response.targetText) }
            let now = ContinuousClock.now
            if lastDelivery == nil || pending.count >= 8 || lastDelivery!.duration(to: now) >= .milliseconds(60) {
                try await receive(pending)
                pending.removeAll(keepingCapacity: true)
                lastDelivery = now
            }
        }
        if !pending.isEmpty { try await receive(pending) }
    }

    private func validate(_ operation: String, revision: Int) throws {
        try Task.checkCancellation()
        guard isActive, token == operation, documentRevision == revision else { throw CancellationError() }
    }

    func suspend() {
        activeHostID = nil
        isActive = false
        cancel()
    }

    func showOriginal() {
        cancel(restoringCompleted: true)
    }

    func cancel(restoringCompleted: Bool = false) {
        guard isWorking || restoringCompleted else { return }
        session?.cancel()
        session = nil
        configuration = nil
        isWorking = false
        let previous = token
        token = nil
        isTranslated = false
        status = String(localized: "Original page")
        if let previous, let document {
            let revision = documentRevision
            let restoration = Task { try await document.restore(token: previous) }
            restorationTask = restoration
            Task {
                do { try await restoration.value } catch {
                    guard token == nil, revision == documentRevision else { return }
                    status = String(localized: "The page could not be restored. Reload to show the original document.")
                }
            }
        }
    }

    func prepareForReaderMode() async throws {
        reset()
        try await restorationTask?.value
    }

    func documentURLDidChange(from previous: URL?, to next: URL?) {
        // In-document anchors retain their translation; a new route does not.
        guard
            previous?.absoluteString.split(separator: "#", maxSplits: 1).first
                != next?.absoluteString.split(separator: "#", maxSplits: 1).first
        else { return }
        reset()
    }

    func reset() {
        cancel(restoringCompleted: true)
        documentRevision &+= 1
        hasDetected = false
        hasRequestedTranslation = false
        sourceID = ""
        isOffered = false
        status = ""
    }
}
