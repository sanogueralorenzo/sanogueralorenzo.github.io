import Foundation
import WebKit

/// Owns Crest's Core Location-backed Geolocation API. Both browser surfaces
/// share this coordinator so site consent, system authorization, document
/// lifetime, and web-standard behavior cannot drift.
@MainActor
final class BrowserGeolocationCoordinator: BrowserSitePermissionObserver {
    /// Asks the core whether a site in a page showing another may use the
    /// person's location: the Space's choice answers, or the person does, and
    /// the core records what they ask it to remember.
    typealias AskSite =
        @MainActor (
            _ origin: SiteOrigin,
            _ topLevelOrigin: SiteOrigin
        ) async -> Bool
    typealias RecoverSystemAuthorization = @MainActor () async -> Void

    /// The messages the geolocation bridge sends.
    private static let messages: [any BrowserGeolocationMessage.Type] = [
        BrowserGeolocationPermissionQuery.self, BrowserGeolocationPositionRequest.self,
        BrowserGeolocationCancellation.self, BrowserGeolocationCancelAll.self,
    ]

    private let webView: WKWebView
    private let permissionCenter: BrowserSitePermissionCenter
    private let service: any BrowserGeolocationServicing
    private let spaceID: UUID
    private let askSite: AskSite
    private let recoverSystemAuthorization: RecoverSystemAuthorization

    private var documentIdentifier = UUID().uuidString
    /// Each instance is a single authorization lifetime, including time spent
    /// awaiting consent and delivery. Removing it permanently invalidates late callbacks.
    private final class Request {
        let nativeIdentifier: String
        let identifier: String
        let origin: SiteOrigin
        let documentIdentifier: String
        let frameDocumentIdentifier: String
        let frame: WKFrameInfo
        let watchesPosition: Bool
        var task: Task<Void, Never>?
        var isAuthorized = false
        var isCompleting = false

        init(
            identifier: String, origin: SiteOrigin, documentIdentifier: String,
            frameDocumentIdentifier: String, frame: WKFrameInfo, watchesPosition: Bool
        ) {
            self.identifier = identifier
            self.origin = origin
            self.documentIdentifier = documentIdentifier
            self.frameDocumentIdentifier = frameDocumentIdentifier
            self.frame = frame
            self.watchesPosition = watchesPosition
            nativeIdentifier = "\(documentIdentifier).\(origin.displayName).\(frameDocumentIdentifier).\(identifier)"
        }
    }

    private var requests: [String: Request] = [:]

    init(
        webView: WKWebView,
        permissionCenter: BrowserSitePermissionCenter,
        service: any BrowserGeolocationServicing,
        spaceID: UUID,
        askSite: @escaping AskSite,
        recoverSystemAuthorization: @escaping RecoverSystemAuthorization
    ) {
        self.webView = webView
        self.permissionCenter = permissionCenter
        self.service = service
        self.spaceID = spaceID
        self.askSite = askSite
        self.recoverSystemAuthorization = recoverSystemAuthorization
        permissionCenter.addObserver(self)
    }

    func receive(_ message: WKScriptMessage) {
        guard message.webView === webView,
            let requestURL = message.frameInfo.request.url,
            let origin = SiteOrigin(url: requestURL),
            SecureOriginCheck(origin: origin).isAllowed,
            let body = message.body as? [String: Any],
            (body["version"] as? Int) == 1,
            let action = body["action"] as? String,
            let frameDocumentIdentifier = body["documentIdentifier"] as? String,
            UUID(uuidString: frameDocumentIdentifier) != nil
        else { return }

        guard let request = Self.messages.lazy.compactMap({ $0.init(action: action, body: body) }).first
        else { return }
        request.handle(
            on: self,
            in: BrowserGeolocationFrame(
                origin: origin, documentIdentifier: documentIdentifier, frame: message.frameInfo,
                frameDocumentIdentifier: frameDocumentIdentifier))
    }

    func synchronizeMainFramePermission() {
        guard let currentURL = webView.url,
            let origin = SiteOrigin(url: currentURL)
        else { return }
        sendPermission(
            origin: origin,
            documentIdentifier: documentIdentifier,
            frame: nil
        )
    }

    func beginNavigation() {
        cancelAll()
        documentIdentifier = UUID().uuidString
    }

    /// Cancels every request `origin` made from the frame document
    /// `frameDocumentIdentifier`.
    func cancelRequests(of origin: SiteOrigin, inFrameDocument frameDocumentIdentifier: String) {
        for request in Array(requests.values)
        where request.origin == origin
            && request.frameDocumentIdentifier == frameDocumentIdentifier
        {
            cancel(nativeIdentifier: request.nativeIdentifier)
        }
    }

    func cancelAll() {
        for identifier in Array(requests.keys) {
            cancel(nativeIdentifier: identifier)
        }
        service.cancelAll()
    }

    func sitePermissionsDidChange(_ change: BrowserSitePermissionChange) {
        for request in Array(requests.values) where change.affects(.location, origin: request.origin, in: spaceID) {
            if change.revokesAuthorization { revoke(request) }
            sendPermission(
                origin: request.origin, documentIdentifier: request.documentIdentifier,
                frame: request.frame, frameDocumentIdentifier: request.frameDocumentIdentifier
            )
        }
        if let url = webView.url, let origin = SiteOrigin(url: url),
            change.affects(.location, origin: origin, in: spaceID)
        {
            synchronizeMainFramePermission()
        }
    }

    func beginRequest(
        identifier: String,
        watchesPosition: Bool,
        options: BrowserGeolocationRequestOptions,
        origin: SiteOrigin,
        documentIdentifier: String,
        frame: WKFrameInfo,
        frameDocumentIdentifier: String
    ) {
        let request = Request(
            identifier: identifier, origin: origin, documentIdentifier: documentIdentifier,
            frameDocumentIdentifier: frameDocumentIdentifier, frame: frame, watchesPosition: watchesPosition
        )
        cancel(nativeIdentifier: request.nativeIdentifier)
        requests[request.nativeIdentifier] = request
        request.task = Task { @MainActor [weak self] in
            guard let self else { return }
            let isAuthorized = await authorize(request)
            guard isCurrentRequest(request), !Task.isCancelled else { return }
            request.task = nil
            sendPermission(
                origin: origin, documentIdentifier: documentIdentifier,
                frame: frame, frameDocumentIdentifier: frameDocumentIdentifier
            )
            guard isAuthorized else {
                revoke(request)
                return
            }
            request.isAuthorized = true
            let receive: @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void = {
                [weak self] result in self?.receive(result, for: request)
            }
            if watchesPosition {
                service.startWatchingPosition(identifier: request.nativeIdentifier, options: options, receive: receive)
            } else {
                service.requestCurrentPosition(identifier: request.nativeIdentifier, options: options, receive: receive)
            }
        }
    }

    private func receive(_ result: Result<BrowserGeolocationPosition, BrowserGeolocationError>, for request: Request) {
        guard isCurrentRequest(request), !request.isCompleting else { return }
        guard hasAuthority(request) else {
            revoke(request)
            return
        }
        request.isCompleting = !request.watchesPosition
        switch result {
        case .success(let position):
            sendPosition(position, request: request)
        case .failure(let error):
            if error.code == .permissionDenied {
                revoke(request)
            } else {
                sendError(error, request: request, requiresAuthority: true)
            }
        }
    }

    private func revoke(_ request: Request) {
        guard isCurrentRequest(request) else { return }
        cancel(nativeIdentifier: request.nativeIdentifier)
        sendError(.permissionDenied, request: request, requiresAuthority: false)
    }

    private func isCurrentRequest(_ request: Request) -> Bool {
        isCurrentDocument(request.documentIdentifier) && requests[request.nativeIdentifier] === request
    }

    private func hasAuthority(_ request: Request) -> Bool {
        let decision = permissionCenter.decision(for: .location, origin: request.origin, in: spaceID)
        // Allow Once deliberately leaves the stored decision at Ask. The
        // request's lifetime carries that consent until an explicit withdrawal.
        return isCurrentRequest(request) && request.isAuthorized && !decision.denies
            && service.currentAuthorization() == .authorized
    }

    private func authorize(_ request: Request) async -> Bool {
        guard isCurrentRequest(request), !Task.isCancelled else { return false }
        let origin = request.origin
        let decision = permissionCenter.decision(for: .location, origin: origin, in: spaceID)
        if decision.denies { return false }
        if decision.verdict == .ask {
            // The core asks the person and records what they ask it to
            // remember, once the system consents to an Allow; the system's
            // consent still gates every position.
            let grants = await askSite(origin, webView.url.flatMap(SiteOrigin.init(url:)) ?? origin)
            guard isCurrentRequest(request) && !Task.isCancelled, grants else { return false }
        }

        guard isCurrentRequest(request) && !Task.isCancelled else { return false }
        guard await systemAuthorizes(),
            isCurrentRequest(request) && !Task.isCancelled
        else { return false }
        guard !permissionCenter.decision(for: .location, origin: origin, in: spaceID).denies else { return false }
        return true
    }

    /// Whether the system lets Crest use the person's location, asking them
    /// when it has not decided and offering to recover a refusal. The page
    /// asks before it sends the person's Allow to the core, so an Allow the
    /// system refuses is never saved.
    func systemAuthorizes() async -> Bool {
        await service.systemAuthorizes(recovering: recoverSystemAuthorization)
    }

    func sendPermission(
        origin: SiteOrigin,
        documentIdentifier: String,
        frame: WKFrameInfo?,
        frameDocumentIdentifier: String? = nil
    ) {
        // The states are the Permissions API's. A site's saved verdict gives
        // them on its own, except a grant, which the system decides.
        let state =
            BrowserWebPermissionState.answering(
                permissionCenter.decision(for: .location, origin: origin, in: spaceID).verdict)
            ?? .answering(service.currentAuthorization())
        send(
            ["type": "permission", "state": state.spelling],
            documentIdentifier: documentIdentifier,
            frame: frame,
            frameDocumentIdentifier: frameDocumentIdentifier
        )
    }

    private func sendPosition(
        _ position: BrowserGeolocationPosition,
        request: Request
    ) {
        send(
            [
                "type": "position",
                "identifier": request.identifier,
                "coords": [
                    "latitude": position.latitude,
                    "longitude": position.longitude,
                    "accuracy": position.accuracy,
                    "altitude": position.altitude.map { $0 as Any } ?? NSNull(),
                    "altitudeAccuracy": position.altitudeAccuracy.map { $0 as Any }
                        ?? NSNull(),
                    "heading": position.heading.map { $0 as Any } ?? NSNull(),
                    "speed": position.speed.map { $0 as Any } ?? NSNull(),
                ],
                "timestamp": position.timestamp,
            ],
            documentIdentifier: request.documentIdentifier,
            frame: request.frame,
            frameDocumentIdentifier: request.frameDocumentIdentifier,
            request: request
        )
    }

    private func sendError(
        _ error: BrowserGeolocationError,
        request: Request,
        requiresAuthority: Bool
    ) {
        send(
            [
                "type": "error", "identifier": request.identifier,
                "code": error.code.rawValue, "message": error.message,
            ],
            documentIdentifier: request.documentIdentifier,
            frame: request.frame,
            frameDocumentIdentifier: request.frameDocumentIdentifier,
            request: requiresAuthority ? request : nil
        )
    }

    private func send(
        _ message: [String: Any],
        documentIdentifier: String,
        frame: WKFrameInfo?,
        frameDocumentIdentifier: String? = nil,
        request: Request? = nil
    ) {
        guard isCurrentDocument(documentIdentifier) else { return }
        var message = message
        if let frameDocumentIdentifier { message["documentIdentifier"] = frameDocumentIdentifier }
        Task { @MainActor [weak self, weak webView] in
            guard let self, isCurrentDocument(documentIdentifier) else { return }
            if let request {
                guard isCurrentRequest(request) else { return }
                guard hasAuthority(request) else {
                    revoke(request)
                    return
                }
            }
            _ = try? await webView?.callAsyncJavaScript(
                "globalThis.__crestGeolocationBridge?.receive(message);",
                arguments: ["message": message],
                in: frame,
                contentWorld: .page
            )
            if let request, request.isCompleting, isCurrentRequest(request) {
                cancel(nativeIdentifier: request.nativeIdentifier)
            }
        }
    }

    func cancel(nativeIdentifier: String) {
        requests.removeValue(forKey: nativeIdentifier)?.task?.cancel()
        service.cancel(identifier: nativeIdentifier)
    }

    private func isCurrentDocument(_ identifier: String) -> Bool {
        identifier == documentIdentifier
    }
}
