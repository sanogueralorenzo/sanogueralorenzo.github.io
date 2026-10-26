import Foundation
import Observation

// MARK: - Types

struct BrowserCredentialUsernameHint: Equatable, Sendable {
    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let username: String
    let capturedAt: Date
}

/// One form message the core decided on, with where it came from, what a
/// fill would write into, and when the page saw it.
struct BrowserCredentialObservation<FillTarget> {
    let message: BrowserCredentialFormMessage
    let frameOrigin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let fillTarget: FillTarget?
    let decision: CredentialCaptureDecision
    let now: Date
}

/// Owns the short-lived credential state for one retained browser page.
///
/// The generic fill target is intentionally opaque here. WebKit pages use a
/// `WKFrameInfo`, while tests can use a harmless value. The immutable Space ID
/// prevents a prompt from following the app's currently selected Space.
@Observable
@MainActor
final class BrowserCredentialPageState<FillTarget> {
    let spaceID: UUID
    @ObservationIgnored private let core: CrestCore

    private(set) var fillRequest: BrowserCredentialFillRequest?
    private(set) var saveCandidate: BrowserCredentialSaveCandidate?

    @ObservationIgnored private var fillTargets: [UUID: FillTarget] = [:]

    /// The form the live request's field belongs to, kept here rather than on
    /// the request itself: a later geometry report has to prove it is about the
    /// same field before it may move the prompt, and the form's ID is the only
    /// name both sides of the bridge agree on.
    @ObservationIgnored private var fillFormID: String?
    @ObservationIgnored private var pendingUsernameHint: BrowserCredentialUsernameHint?
    @ObservationIgnored private var usernameExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSaveCandidate: BrowserCredentialSaveCandidate?
    @ObservationIgnored private var candidateExpirationTask: Task<Void, Never>?

    init(spaceID: UUID, core: CrestCore) {
        self.spaceID = spaceID
        self.core = core
    }

    /// Applies one validated form message. The portable core decides what
    /// the message means from its redacted facts; the username and password
    /// values stay here. Without a core answer nothing is captured or offered.
    func receive(
        _ message: BrowserCredentialFormMessage,
        frameOrigin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        isMainFrame: Bool,
        fillTarget: FillTarget?
    ) {
        guard let event = message.event.captureEvent else {
            followField(message, frameOrigin: frameOrigin, isMainFrame: isMainFrame)
            return
        }
        let now = Date.now
        let facts = CredentialFormFacts(
            event: event, frameOrigin: frameOrigin, topLevelOrigin: topLevelOrigin, isMainFrame: isMainFrame,
            hasFormID: message.formID != nil, hasUsername: message.username != nil,
            hasPassword: message.password != nil, passwordKind: message.passwordKind,
            hasVisiblePasswordField: message.hasVisiblePasswordField, hasFillTarget: fillTarget != nil)
        guard
            let decision = captureDecision(
                facts, usernameHint: pendingUsernameHint,
                pendingCandidate: message.event.weighsPendingCandidate ? pendingSaveCandidate : nil, now: now)
        else {
            // Fail safe: close any fill prompt this page shows and capture nothing.
            if message.event.closesFillWhenRefused { dismissFillRequest() }
            return
        }
        if decision.clearsUsernameHint { clearUsernameHint() }
        decision.action.take(
            BrowserCredentialObservation(
                message: message, frameOrigin: frameOrigin, topLevelOrigin: topLevelOrigin, fillTarget: fillTarget,
                decision: decision, now: now),
            on: self)
    }

    /// A geometry report only moves the prompt already on show, and only for
    /// the main-frame field of the same form.
    private func followField(
        _ message: BrowserCredentialFormMessage,
        frameOrigin: CredentialOrigin,
        isMainFrame: Bool
    ) {
        guard isMainFrame,
            let request = fillRequest,
            request.fieldRect != nil,
            let formID = message.formID,
            formID == fillFormID,
            request.origin == frameOrigin,
            let fieldRect = message.fieldRect,
            fieldRect != request.fieldRect
        else {
            return
        }
        fillRequest = request.following(fieldRect)
    }

    func fillContext(
        for requestID: UUID,
        credential: BrowserCredential
    ) throws -> (request: BrowserCredentialFillRequest, target: FillTarget) {
        guard let request = fillRequest,
            request.id == requestID,
            fillAllowed(from: .saved, into: request.passwordKind),
            credential.descriptor.spaceID == spaceID,
            credential.descriptor.origin == request.origin,
            let target = fillTargets[requestID]
        else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        return (request, target)
    }

    func generatedPasswordFillContext(
        for requestID: UUID
    ) throws -> (request: BrowserCredentialFillRequest, target: FillTarget) {
        guard let request = fillRequest,
            request.id == requestID,
            fillAllowed(from: .generated, into: request.passwordKind),
            let target = fillTargets[requestID]
        else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        return (request, target)
    }

    func completeFill(username: String, requestID: UUID) {
        guard let request = fillRequest, request.id == requestID else { return }
        let facts = CredentialFormFacts(
            event: .filled, frameOrigin: request.origin, topLevelOrigin: request.topLevelOrigin,
            isMainFrame: request.fieldRect != nil, hasFormID: fillFormID != nil, hasUsername: true, hasPassword: false,
            passwordKind: request.passwordKind, hasVisiblePasswordField: nil, hasFillTarget: true)
        if let decision = captureDecision(facts, usernameHint: nil, pendingCandidate: nil, now: .now),
            decision.action == .rememberUsername
        {
            rememberUsername(
                username, origin: request.origin, topLevelOrigin: request.topLevelOrigin,
                lifetime: decision.usernameHintLifetime)
        }
        dismissFillRequest()
    }

    func completeGeneratedPasswordFill(requestID: UUID) {
        guard fillRequest?.id == requestID else { return }
        dismissFillRequest()
    }

    func dismissFillRequest() {
        fillFormID = nil
        guard let request = fillRequest else { return }
        fillTargets[request.id] = nil
        fillRequest = nil
    }

    func dismissSaveCandidate() {
        pendingSaveCandidate = nil
        candidateExpirationTask?.cancel()
        candidateExpirationTask = nil
        saveCandidate = nil
    }

    func didChangeTopLevelURL(to url: URL?) {
        guard let hint = pendingUsernameHint,
            let url,
            let currentOrigin = CredentialOrigin(url: url),
            currentOrigin != hint.topLevelOrigin
        else { return }
        clearUsernameHint()
    }

    func didStartNavigation() {
        dismissFillRequest()
    }

    func webContentProcessDidTerminate() {
        reset()
    }

    func reset() {
        dismissFillRequest()
        dismissSaveCandidate()
        clearUsernameHint()
    }

    private func rememberUsername(
        _ username: String,
        origin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        lifetime: TimeInterval
    ) {
        let hint = BrowserCredentialUsernameHint(
            origin: origin,
            topLevelOrigin: topLevelOrigin,
            username: username,
            capturedAt: .now
        )
        pendingUsernameHint = hint
        usernameExpirationTask?.cancel()
        usernameExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled,
                self?.pendingUsernameHint?.capturedAt == hint.capturedAt
            else { return }
            self?.pendingUsernameHint = nil
            self?.usernameExpirationTask = nil
        }
    }

    /// What one form observation does to the page's credential state. Nil
    /// when the core refuses the facts; the caller then captures and offers
    /// nothing. Only the facts cross: the username and password stay here.
    private func captureDecision(
        _ facts: CredentialFormFacts,
        usernameHint: BrowserCredentialUsernameHint?,
        pendingCandidate: BrowserCredentialSaveCandidate?,
        now: Date
    ) -> CredentialCaptureDecision? {
        let capture = CredentialCapture(
            facts: facts,
            hint: usernameHint.map {
                CredentialUsernameHint(
                    origin: $0.origin, topLevelOrigin: $0.topLevelOrigin,
                    capturedAt: $0.capturedAt.timeIntervalSince1970)
            },
            pending: pendingCandidate.map {
                CredentialPendingCandidate(origin: $0.origin, submittedAt: $0.submittedAt.timeIntervalSince1970)
            },
            now: now.timeIntervalSince1970)
        guard let decision = try? core.query(capture), decision.candidateLifetime > 0, decision.usernameHintLifetime > 0
        else { return nil }
        return decision
    }

    /// Whether a fill may take a saved credential or a generated password into
    /// a field of this kind. A core that refuses fills nothing.
    private func fillAllowed(from source: CredentialFillSource, into passwordKind: CredentialPasswordKind) -> Bool {
        (try? core.query(CredentialFill(source: source, passwordKind: passwordKind)))?.isAllowed ?? false
    }

    /// The username the core chose: the message's own, or the remembered one.
    private func username(
        from source: CredentialUsernameSource,
        explicitUsername: String?
    ) -> String? {
        switch source {
        case .explicit: explicitUsername
        case .hint: pendingUsernameHint?.username
        case .none: nil
        }
    }

    private func clearUsernameHint() {
        usernameExpirationTask?.cancel()
        usernameExpirationTask = nil
        pendingUsernameHint = nil
    }
}

// MARK: - Actions - Capture

extension BrowserCredentialPageState: CredentialCapturePerformer {
    func ignore(_ observation: BrowserCredentialObservation<FillTarget>) {}

    func rememberUsername(_ observation: BrowserCredentialObservation<FillTarget>) {
        guard let username = observation.message.username else { return }
        rememberUsername(
            username, origin: observation.frameOrigin, topLevelOrigin: observation.topLevelOrigin,
            lifetime: observation.decision.usernameHintLifetime)
    }

    func dismissFill(_ observation: BrowserCredentialObservation<FillTarget>) {
        dismissFillRequest()
    }

    func offerFill(_ observation: BrowserCredentialObservation<FillTarget>) {
        let message = observation.message
        let decision = observation.decision
        guard let passwordKind = message.passwordKind, let formID = message.formID,
            let fillTarget = observation.fillTarget
        else { return }
        let request = BrowserCredentialFillRequest(
            id: UUID(),
            origin: observation.frameOrigin,
            topLevelOrigin: observation.topLevelOrigin,
            usernameHint: username(from: decision.usernameSource, explicitUsername: message.username),
            passwordKind: passwordKind,
            isCrossOriginFrame: decision.isCrossOriginFrame,
            requestedAt: observation.now,
            fieldRect: decision.anchorsToField ? message.fieldRect : nil
        )
        if let previousRequest = fillRequest {
            fillTargets[previousRequest.id] = nil
        }
        fillTargets[request.id] = fillTarget
        fillFormID = formID
        fillRequest = request
    }

    func captureCandidate(_ observation: BrowserCredentialObservation<FillTarget>) {
        let message = observation.message
        let decision = observation.decision
        guard
            let username = username(from: decision.usernameSource, explicitUsername: message.username),
            let password = message.password,
            let passwordKind = message.passwordKind
        else { return }
        dismissSaveCandidate()
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: observation.frameOrigin,
            topLevelOrigin: observation.topLevelOrigin,
            username: username,
            password: password,
            passwordKind: passwordKind,
            isCrossOriginFrame: decision.isCrossOriginFrame,
            submittedAt: observation.now
        )
        dismissFillRequest()
        clearUsernameHint()
        pendingSaveCandidate = candidate
        let lifetime = decision.candidateLifetime
        candidateExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled, let self else { return }
            if self.pendingSaveCandidate?.id == candidate.id {
                self.pendingSaveCandidate = nil
            }
            if self.saveCandidate?.id == candidate.id {
                self.saveCandidate = nil
            }
            self.candidateExpirationTask = nil
        }
    }

    func offerSave(_ observation: BrowserCredentialObservation<FillTarget>) {
        guard let candidate = pendingSaveCandidate else { return }
        pendingSaveCandidate = nil
        saveCandidate = candidate
    }

    func keepPending(_ observation: BrowserCredentialObservation<FillTarget>) {}

    func discardPending(_ observation: BrowserCredentialObservation<FillTarget>) {
        pendingSaveCandidate = nil
    }
}

enum BrowserCredentialFillError: Error, Equatable {
    case staleOrMismatchedRequest
    case formChanged
}
