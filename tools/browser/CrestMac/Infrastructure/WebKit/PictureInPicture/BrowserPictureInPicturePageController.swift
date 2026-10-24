import WebKit

@MainActor
final class BrowserPictureInPicturePageController: BrowserPagePictureInPictureController,
    BrowserAutomaticPictureInPictureClient
{
    private struct FrameCandidate {
        let frame: WKFrameInfo
        let documentID: String
        let videoID: String
        let score: Double
    }

    private struct AutomaticRequest {
        let id: UUID
        let candidate: FrameCandidate
    }

    private weak var webView: WKWebView?
    private let coordinator: BrowserAutomaticPictureInPictureCoordinator
    private var candidates: [String: FrameCandidate] = [:]
    private var activeDocuments: Set<String> = [] {
        didSet { residencyProtectionMayHaveChanged() }
    }
    private var nativeIsActive = false {
        didSet { residencyProtectionMayHaveChanged() }
    }
    private var acceptsEvents = true
    private var automaticRequest: AutomaticRequest?
    private var completion: (@MainActor (Bool) -> Void)? {
        didSet { residencyProtectionMayHaveChanged() }
    }
    private var timeout: Task<Void, Never>?
    /// Whether the controller kept the page's video on screen when it last
    /// said so.
    private var reportedResidencyProtection = false
    /// Runs when the controller starts or stops keeping the page's video on
    /// screen, so the page reports its media to the core.
    var residencyProtectionChanged: (@MainActor () -> Void)?

    var isPictureInPictureActive: Bool { nativeIsActive || !activeDocuments.isEmpty }
    var canRestoreSource: Bool { acceptsEvents && isPictureInPictureActive }
    var protectsPageResidency: Bool { isPictureInPictureActive || completion != nil }
    var canAutomaticallyEnterPictureInPicture: Bool {
        !candidates.isEmpty && !isPictureInPictureActive && webView != nil
    }

    init(webView: WKWebView, coordinator: BrowserAutomaticPictureInPictureCoordinator = .shared) {
        self.webView = webView
        self.coordinator = coordinator
        coordinator.register(self)
        BrowserPictureInPictureContentBridge.shared.register(self, webView: webView)
    }

    func leaveTab() { coordinator.request(from: self) }

    private func residencyProtectionMayHaveChanged() {
        guard protectsPageResidency != reportedResidencyProtection else { return }
        reportedResidencyProtection = protectsPageResidency
        residencyProtectionChanged?()
    }

    func returnToTab() {
        coordinator.cancel(self)
        refreshCandidates()
    }

    func navigationDidCommit() { refreshCandidates() }

    private func refreshCandidates() {
        acceptsEvents = true
        webView?.evaluateJavaScript(
            "globalThis.__crestPictureInPicture?.emit(); null",
            in: nil, in: BrowserPictureInPictureContentBridge.contentWorld
        ) { _ in }
    }

    func nativePresentationDidChange(isActive: Bool) {
        nativeIsActive = isActive
        if !isActive {
            activeDocuments.removeAll()
            if completion == nil { automaticRequest = nil }
        }
    }

    func invalidate() {
        acceptsEvents = false
        coordinator.cancel(self)
        if isPictureInPictureActive { webView?.closeAllMediaPresentations(completionHandler: {}) }
        candidates.removeAll()
        activeDocuments.removeAll()
        nativeIsActive = false
    }

    func receive(_ message: WKScriptMessage) {
        guard acceptsEvents, message.webView === webView,
            let body = message.body as? [String: Any],
            let documentID = body["documentID"] as? String, documentID.count <= 64,
            let kind = body["kind"] as? String
        else { return }
        if kind == "removed" {
            candidates[documentID] = nil
            activeDocuments.remove(documentID)
            return
        }
        if kind == "request" {
            guard body["requestID"] as? String == automaticRequest?.id.uuidString else { return }
            let succeeded = body["succeeded"] as? Bool == true
            if succeeded { activeDocuments.insert(documentID) }
            finish(succeeded: succeeded)
            return
        }
        guard kind == "state" else { return }
        if body["active"] as? Bool == true {
            activeDocuments.insert(documentID)
        } else {
            activeDocuments.remove(documentID)
        }
        guard body["eligible"] as? Bool == true,
            let videoID = body["videoID"] as? String, videoID.count <= 32,
            let score = body["score"] as? Double, score.isFinite,
            candidates[documentID] != nil || candidates.count < 64
        else {
            candidates[documentID] = nil
            return
        }
        candidates[documentID] = FrameCandidate(
            frame: message.frameInfo,
            documentID: documentID, videoID: videoID, score: score)
    }

    func beginAutomaticPictureInPicture(completion: @escaping @MainActor (Bool) -> Void) {
        guard let webView, let candidate = candidates.values.max(by: { $0.score < $1.score }) else {
            completion(false)
            return
        }
        let request = AutomaticRequest(id: UUID(), candidate: candidate)
        automaticRequest = request
        self.completion = completion
        // evaluateJavaScript provides the native user-activation context. Keep
        // the request synchronous inside that evaluation; awaiting discovery
        // before requestPictureInPicture can lose the activation.
        let arguments = [candidate.documentID, candidate.videoID, request.id.uuidString]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
            let encoded = String(data: data, encoding: .utf8)
        else {
            finish(succeeded: false)
            return
        }
        webView.evaluateJavaScript(
            "globalThis.__crestPictureInPicture?.enter(...\(encoded)) ?? false",
            in: candidate.frame, in: BrowserPictureInPictureContentBridge.contentWorld
        ) { [weak self] result in
            guard let self, self.automaticRequest?.id == request.id else { return }
            switch result {
            case .success(let value) where value as? Bool == true: break
            default: self.finish(succeeded: false)
            }
        }
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard let self, self.automaticRequest?.id == request.id, self.completion != nil else { return }
            self.cancelAutomaticPictureInPicture()
        }
    }

    func cancelAutomaticPictureInPicture() {
        if let request = automaticRequest {
            let id = request.id.uuidString
            webView?.evaluateJavaScript(
                "globalThis.__crestPictureInPicture?.cancel('\(id)'); null",
                in: request.candidate.frame, in: BrowserPictureInPictureContentBridge.contentWorld
            ) { _ in }
        }
        automaticRequest = nil
        finish(succeeded: false)
    }

    private func finish(succeeded: Bool) {
        timeout?.cancel()
        timeout = nil
        let callback = completion
        completion = nil
        if !succeeded { automaticRequest = nil }
        callback?(succeeded)
    }
}
