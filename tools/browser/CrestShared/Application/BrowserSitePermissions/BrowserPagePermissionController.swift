import Foundation
import Observation

/// Owns unanswered requests for one page. A detached page cannot ask through
/// another page's controls, and dismissal never creates a saved denial.
@Observable
@MainActor
final class BrowserPagePermissionController {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let permission: SitePermission
        let origin: SiteOrigin
        let topLevelOrigin: SiteOrigin
        let spaceName: String
    }

    private(set) var current: Request?
    private(set) var generation = UUID()
    @ObservationIgnored private var isPresentationAvailable = false
    @ObservationIgnored private var requests: [Request] = []
    /// Who waits on each request, each by its own token, so one that no
    /// longer waits can leave without answering the others.
    @ObservationIgnored private var completions:
        [UUID: [(token: UUID, callback: (BrowserSitePermissionPromptResponse?) -> Void)]] = [:]

    func setPresentationAvailable(_ available: Bool) {
        isPresentationAvailable = available
        if !available { cancelAll() }
    }

    func request(
        _ permission: SitePermission,
        origin: SiteOrigin,
        topLevelOrigin: SiteOrigin,
        spaceName: String,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping (BrowserSitePermissionPromptResponse?) -> Void
    ) {
        guard isPresentationAvailable else {
            completion(nil)
            return
        }
        let token = UUID()
        let request: Request
        if let existing = requests.first(where: {
            $0.permission == permission && $0.origin == origin
                && $0.topLevelOrigin == topLevelOrigin
        }) {
            request = existing
            completions[existing.id, default: []].append((token, completion))
        } else {
            request = Request(
                permission: permission, origin: origin,
                topLevelOrigin: topLevelOrigin, spaceName: spaceName
            )
            requests.append(request)
            completions[request.id] = [(token, completion)]
            current = requests.first
        }
        dismissal?.attach { [weak self] in self?.withdraw(token, from: request.id) }
    }

    /// One waiting on `requestID` no longer does: it hears no answer, as a
    /// request nobody could show does, and a request nobody waits on any more
    /// leaves the queue.
    private func withdraw(_ token: UUID, from requestID: UUID) {
        guard var waiting = completions[requestID], let index = waiting.firstIndex(where: { $0.token == token }) else {
            return
        }
        let withdrawn = waiting.remove(at: index)
        if waiting.isEmpty {
            completions.removeValue(forKey: requestID)
            requests.removeAll { $0.id == requestID }
            if current?.id == requestID { current = requests.first }
        } else {
            completions[requestID] = waiting
        }
        withdrawn.callback(nil)
    }

    func resolve(_ id: UUID, response: BrowserSitePermissionPromptResponse) {
        guard current?.id == id else { return }
        requests.removeFirst()
        let callbacks = completions.removeValue(forKey: id) ?? []
        current = requests.first
        for waiting in callbacks { waiting.callback(response) }
    }

    func response(
        to permission: SitePermission,
        origin: SiteOrigin,
        topLevelOrigin: SiteOrigin,
        spaceName: String,
        dismissal: BrowserPromptDismissal? = nil
    ) async -> BrowserSitePermissionPromptResponse {
        await withCheckedContinuation { continuation in
            request(
                permission, origin: origin, topLevelOrigin: topLevelOrigin, spaceName: spaceName, dismissal: dismissal
            ) { response in
                continuation.resume(returning: response ?? .denyOnce)
            }
        }
    }

    func cancelAll() {
        generation = UUID()
        let callbacks = requests.flatMap { completions[$0.id] ?? [] }
        requests.removeAll()
        completions.removeAll()
        current = nil
        for waiting in callbacks { waiting.callback(nil) }
    }
}
