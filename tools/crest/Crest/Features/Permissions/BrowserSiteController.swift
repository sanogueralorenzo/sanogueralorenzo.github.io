import AVFoundation
import AppKit
import AuthenticationServices
import CoreLocation
import Foundation
import Security
import UserNotifications
import WebKit

@MainActor
final class BrowserSiteController: NSObject, WKScriptMessageHandler, @preconcurrency CLLocationManagerDelegate {
    struct LocationRequest {
        let id: String
        let origin: String
        let document: String
        let frame: WKFrameInfo
        let generation: Int
        let watch: Bool
    }
    weak var page: BrowserPage?
    private let manager = CLLocationManager()
    private var authorization: [CheckedContinuation<Bool, Never>] = []
    private var locationRequests: [String: LocationRequest] = [:]
    private var notifications: Set<String> = []
    private var permissionQuestions: [String: Task<Bool, Never>] = [:]
    var frames: [String: WKFrameInfo] = [:]
    private var captureGrants: [BrowserSitePermission.Kind: Set<String>] = [:]
    func recordCapture(_ kinds: [BrowserSitePermission.Kind], origin: String) {
        for kind in kinds { captureGrants[kind, default: []].insert(origin) }
    }

    init(page: BrowserPage) {
        self.page = page
        super.init()
        manager.delegate = self
        let controller = page.webView.configuration.userContentController
        controller.add(self, contentWorld: .defaultClient, name: "crestDocumentActivity")
        controller.addUserScript(
            WKUserScript(
                source: Self.activityScript, injectionTime: .atDocumentStart,
                forMainFrameOnly: false, in: .defaultClient))
        controller.add(self, contentWorld: .page, name: "crestGeolocation")
        controller.add(self, contentWorld: .page, name: "crestHostedNotifications")
        controller.addUserScript(
            WKUserScript(
                source: BrowserSiteScripts.geolocation, injectionTime: .atDocumentStart,
                forMainFrameOnly: false, in: .page))
        controller.addUserScript(
            WKUserScript(
                source: BrowserSiteScripts.notifications, injectionTime: .atDocumentStart,
                forMainFrameOnly: true, in: .page))
    }

    static func origin(_ value: WKSecurityOrigin) -> String? {
        let scheme = value.protocol.lowercased()
        let host = value.host.lowercased()
        guard !host.isEmpty, ["http", "https"].contains(scheme) else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        if value.port > 0 && !((scheme == "https" && value.port == 443) || (scheme == "http" && value.port == 80)) {
            parts.port = value.port
        }
        return parts.string
    }

    static func secure(_ origin: String) -> Bool {
        guard let url = URL(string: origin) else { return false }
        return url.scheme == "https" || ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")
    }

    func decide(_ kind: BrowserSitePermission.Kind, origin: WKSecurityOrigin, frame: WKFrameInfo) async -> Bool {
        guard let page, frame.webView === page.webView, let value = Self.origin(origin) else { return false }
        return await decide(kind, origin: value, generation: page.documentRevision)
    }

    func decide(_ kind: BrowserSitePermission.Kind, origin: String, generation: Int) async -> Bool {
        guard Self.secure(origin), let page, let store = page.owner,
            store.session.spaces.contains(where: { $0.id == page.spaceID }), generation == page.documentRevision
        else { return false }
        let decision = store.permission(kind, origin: origin, spaceID: page.spaceID)
        if decision != .ask { return decision == .allow }
        let key = "\(generation).\(origin).\(kind.rawValue)"
        if let pending = permissionQuestions[key] { return await pending.value }
        guard permissionQuestions.isEmpty else { return false }
        let pending = Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Allow \(kind.label.lowercased())?"
            alert.informativeText = "\(origin) is requesting access in this Space."
            alert.addButton(withTitle: "Don't Allow")
            alert.addButton(withTitle: "Allow")
            let allowed = await BrowserDialogs.ask(alert, in: page.webView.window) == .alertSecondButtonReturn
            guard !Task.isCancelled, generation == page.documentRevision,
                store.session.spaces.contains(where: { $0.id == page.spaceID })
            else { return false }
            let latest = store.permission(kind, origin: origin, spaceID: page.spaceID)
            if latest != .ask { return latest == .allow }
            store.setPermission(kind, origin: origin, spaceID: page.spaceID, decision: allowed ? .allow : .deny)
            return allowed
        }
        permissionQuestions[key] = pending
        defer { permissionQuestions[key] = nil }
        return await pending.value
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "crestDocumentActivity", let page, message.webView === page.webView,
            let body = message.body as? [String: Any], let id = body["document"] as? String, UUID(uuidString: id) != nil
        {
            if let selection = body["selection"] as? String {
                (page.webView as? BrowserNativeWebView)?.contextSelection = String(selection.prefix(4096))
                return
            }
            if body["removed"] as? Bool == true {
                page.frameEdits[id] = nil
                frames[id] = nil
            } else if let dirty = body["dirty"] as? Bool, frames.count < 128 || frames[id] != nil {
                page.frameEdits[id] = dirty
                frames[id] = message.frameInfo
            }
            page.hasUnsavedEdits = page.documentHasEdits || page.frameEdits.values.contains(true)
            return
        }
        guard let page, message.webView === page.webView, let origin = Self.origin(message.frameInfo.securityOrigin),
            Self.secure(origin), let body = message.body as? [String: Any], body["version"] as? Int == 1,
            let action = body["action"] as? String
        else { return }
        let generation = page.documentRevision
        if message.name == "crestGeolocation" {
            receiveLocation(body, action: action, origin: origin, frame: message.frameInfo, generation: generation)
        } else if message.name == "crestHostedNotifications", message.frameInfo.isMainFrame {
            receiveNotification(body, action: action, origin: origin, frame: message.frameInfo, generation: generation)
        }
    }

    private func receiveLocation(
        _ body: [String: Any], action: String, origin: String, frame: WKFrameInfo, generation: Int
    ) {
        guard let document = body["documentIdentifier"] as? String, UUID(uuidString: document) != nil else { return }
        if action == "cancelAll" {
            locationRequests = locationRequests.filter { $0.value.document != document || $0.value.origin != origin }
            if locationRequests.isEmpty { manager.stopUpdatingLocation() }
            return
        }
        if action == "queryPermission" {
            guard let page else { return }
            var state = page.owner?.permission(.location, origin: origin, spaceID: page.spaceID) ?? .deny
            if [.denied, .restricted].contains(manager.authorizationStatus) { state = .deny }
            send(
                [
                    "type": "permission", "documentIdentifier": document,
                    "state": state == .allow ? "granted" : state == .deny ? "denied" : "prompt",
                ],
                to: frame, generation: generation, bridge: "__crestGeolocationBridge")
            return
        }
        guard let identifier = body["identifier"] as? String, identifier.count < 200 else { return }
        let key = origin + document + identifier
        if action == "cancel" {
            locationRequests[key] = nil
            return
        }
        guard ["getCurrentPosition", "watchPosition"].contains(action), locationRequests.count < 128 else { return }
        Task {
            guard await decide(.location, origin: origin, generation: generation), await systemLocationAuthorized(),
                let page, page.documentRevision == generation,
                page.owner?.permission(.location, origin: origin, spaceID: page.spaceID) == .allow
            else {
                send(
                    [
                        "type": "error", "documentIdentifier": document, "identifier": identifier, "code": 1,
                        "message": "Location permission was denied.",
                    ],
                    to: frame, generation: generation, bridge: "__crestGeolocationBridge")
                return
            }
            locationRequests[key] = LocationRequest(
                id: identifier, origin: origin, document: document, frame: frame,
                generation: generation, watch: action == "watchPosition")
            let options = body["options"] as? [String: Any]
            manager.desiredAccuracy =
                options?["enableHighAccuracy"] as? Bool == true
                ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
            manager.startUpdatingLocation()
        }
    }

    private func systemLocationAuthorized() async -> Bool {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                authorization.append(continuation)
                manager.requestWhenInUseAuthorization()
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    self?.finishLocationAuthorization()
                }
            }
        default: return false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined { finishLocationAuthorization() }
    }

    private func finishLocationAuthorization() {
        let allowed = manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways
        let pending = authorization
        authorization.removeAll()
        for continuation in pending { continuation.resume(returning: allowed) }
        if !allowed { locationManager(manager, didFailWithError: CLError(.denied)) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        for (key, request) in locationRequests {
            guard let page, request.generation == page.documentRevision,
                page.owner?.permission(.location, origin: request.origin, spaceID: page.spaceID) == .allow
            else {
                locationRequests[key] = nil
                continue
            }
            send(
                [
                    "type": "position", "documentIdentifier": request.document, "identifier": request.id,
                    "timestamp": location.timestamp.timeIntervalSince1970 * 1000,
                    "coords": [
                        "latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
                        "accuracy": location.horizontalAccuracy,
                        "altitude": location.verticalAccuracy >= 0 ? location.altitude as Any : NSNull(),
                        "altitudeAccuracy": location.verticalAccuracy >= 0
                            ? location.verticalAccuracy as Any : NSNull(),
                        "heading": location.course >= 0 ? location.course as Any : NSNull(),
                        "speed": location.speed >= 0 ? location.speed as Any : NSNull(),
                    ],
                ],
                to: request.frame, generation: request.generation, bridge: "__crestGeolocationBridge")
            if !request.watch { locationRequests[key] = nil }
        }
        if locationRequests.isEmpty { manager.stopUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        for request in locationRequests.values {
            send(
                [
                    "type": "error", "documentIdentifier": request.document, "identifier": request.id, "code": 2,
                    "message": "The current location is unavailable.",
                ], to: request.frame, generation: request.generation, bridge: "__crestGeolocationBridge")
        }
        locationRequests.removeAll()
        manager.stopUpdatingLocation()
    }

    private func receiveNotification(
        _ body: [String: Any], action: String, origin: String, frame: WKFrameInfo, generation: Int
    ) {
        guard let page, let store = page.owner else { return }
        if action == "queryPermission" || action == "requestPermission" {
            let requestID = String((body["requestID"] as? String ?? "initial").prefix(200))
            Task {
                var allowed = store.permission(.notifications, origin: origin, spaceID: page.spaceID) == .allow
                if action == "requestPermission" {
                    allowed = await decide(.notifications, origin: origin, generation: generation)
                    if allowed {
                        allowed =
                            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
                                .alert, .sound,
                            ])) == true
                    }
                }
                let system = await UNUserNotificationCenter.current().notificationSettings()
                allowed = allowed && [.authorized, .provisional].contains(system.authorizationStatus)
                let denied = store.permission(.notifications, origin: origin, spaceID: page.spaceID) == .deny
                send(
                    [
                        "type": "permission", "requestID": requestID,
                        "permission": allowed ? "granted" : denied ? "denied" : "default",
                    ],
                    to: frame, generation: generation, bridge: "__crestHostedNotificationBridge")
            }
            return
        }
        guard let identifier = body["identifier"] as? String, identifier.count <= 200 else { return }
        let nativeID = "\(page.id).\(generation).\(identifier)"
        if action == "close" {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [nativeID])
            notifications.remove(nativeID)
            return
        }
        guard action == "create", notifications.count < 32,
            store.permission(.notifications, origin: origin, spaceID: page.spaceID) == .allow,
            let title = body["title"] as? String, let text = body["body"] as? String
        else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard [.authorized, .provisional].contains(settings.authorizationStatus),
                generation == page.documentRevision,
                store.permission(.notifications, origin: origin, spaceID: page.spaceID) == .allow
            else { return }
            let content = UNMutableNotificationContent()
            content.title = String(title.prefix(256))
            content.body = String(text.prefix(4096))
            content.subtitle = URL(string: origin)?.host ?? origin
            content.userInfo = ["tabID": page.id.uuidString, "identifier": identifier, "generation": generation]
            if body["silent"] as? Bool != true { content.sound = .default }
            do {
                try await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: nativeID, content: content, trigger: nil))
                guard generation == page.documentRevision,
                    store.permission(.notifications, origin: origin, spaceID: page.spaceID) == .allow
                else {
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [nativeID])
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [nativeID])
                    return
                }
                notifications.insert(nativeID)
                send(
                    ["type": "event", "identifier": identifier, "event": "show"], to: frame, generation: generation,
                    bridge: "__crestHostedNotificationBridge")
            } catch {
                send(
                    ["type": "event", "identifier": identifier, "event": "error"], to: frame, generation: generation,
                    bridge: "__crestHostedNotificationBridge")
            }
        }
    }

    func send(_ body: [String: Any], to frame: WKFrameInfo?, generation: Int, bridge: String) {
        guard let page, page.documentRevision == generation,
            let data = try? JSONSerialization.data(withJSONObject: body),
            let value = String(data: data, encoding: .utf8)
        else { return }
        Task {
            _ = try? await page.webView.callAsyncJavaScript(
                "globalThis[bridge]?.receive(JSON.parse(payload));",
                arguments: ["bridge": bridge, "payload": value], in: frame, contentWorld: .page)
        }
    }

    func navigationStarted() {
        for pending in permissionQuestions.values { pending.cancel() }
        permissionQuestions.removeAll()
        locationRequests.removeAll()
        frames.removeAll()
        manager.stopUpdatingLocation()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(notifications))
        notifications.removeAll()
    }

    func permissionChanged() {
        guard let page else { return }
        locationRequests = locationRequests.filter {
            page.owner?.permission(.location, origin: $0.value.origin, spaceID: page.spaceID) == .allow
        }
        if locationRequests.isEmpty { manager.stopUpdatingLocation() }
        for (kind, origins) in captureGrants
        where origins.contains(where: { page.owner?.permission(kind, origin: $0, spaceID: page.spaceID) != .allow }) {
            if kind == .camera { page.webView.setCameraCaptureState(.none) {} }
            if kind == .microphone { page.webView.setMicrophoneCaptureState(.none) {} }
            if kind == .screenCapture { (page.webView as? BrowserNativeWebView)?.stopDisplayCapture() }
            captureGrants[kind] = nil
        }
        if let url = page.url, let origin = BrowserStore.siteOrigin(url) {
            if page.owner?.permission(.notifications, origin: origin, spaceID: page.spaceID) != .allow {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(notifications))
                UNUserNotificationCenter.current().removePendingNotificationRequests(
                    withIdentifiers: Array(notifications))
                notifications.removeAll()
            }
        }
    }

    func invalidate() {
        navigationStarted()
        finishLocationAuthorization()
        page?.webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "crestDocumentActivity", contentWorld: .defaultClient)
        page?.webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "crestGeolocation", contentWorld: .page)
        page?.webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "crestHostedNotifications", contentWorld: .page)
        page = nil
    }
}

extension BrowserStore {
    static func siteOrigin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host else {
            return nil
        }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host.lowercased()
        if let port = url.port, !((scheme == "https" && port == 443) || (scheme == "http" && port == 80)) {
            parts.port = port
        }
        return parts.string
    }
    func permission(_ kind: BrowserSitePermission.Kind, origin: String, spaceID: UUID) -> BrowserSitePermission.Decision
    {
        session.spaces.first(where: { $0.id == spaceID })?.permissions.first(where: {
            $0.kind == kind && $0.origin == origin
        })?.decision ?? .ask
    }
    func setPermission(
        _ kind: BrowserSitePermission.Kind, origin: String, spaceID: UUID, decision: BrowserSitePermission.Decision
    ) {
        guard let index = session.spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        session.spaces[index].permissions.removeAll { $0.kind == kind && $0.origin == origin }
        if decision != .ask {
            session.spaces[index].permissions.append(
                BrowserSitePermission(origin: origin, kind: kind, decision: decision))
        }
        for page in pages.values where page.spaceID == spaceID { page.siteController?.permissionChanged() }
        changed()
    }
}

extension BrowserSiteController {
    static let activityScript = #"""
        (() => {
          const documentID = crypto.randomUUID(); const edited = new WeakSet();
          addEventListener('contextmenu', event => {
            if(!event.isTrusted) return;
            const selection = event.target?.type === 'password' ? '' : String(getSelection() || '');
            webkit.messageHandlers.crestDocumentActivity.postMessage({document:documentID,selection});
          },true);
          const send = removed => {
            const dirty = [...document.querySelectorAll('input,textarea,select,[contenteditable=true]')].some(e =>
              (e.isContentEditable ? edited.has(e) : (['checkbox','radio'].includes(e.type) ? e.checked !== e.defaultChecked :
              e.tagName === 'SELECT' ? [...e.options].some(o => o.selected !== o.defaultSelected) : e.value !== e.defaultValue)));
            try { webkit.messageHandlers.crestDocumentActivity.postMessage({document:documentID,dirty,removed}); } catch {}
          };
          for(const type of ['input','change','reset']) addEventListener(type,event => { if(event.target?.isContentEditable) edited.add(event.target); queueMicrotask(() => send(false)); },true);
          addEventListener('DOMContentLoaded',() => send(false),{once:true});
          addEventListener('pagehide',() => send(true),{once:true});
        })();
        """#
}
