import Foundation
import Observation

@Observable
@MainActor
final class BrowserTransientBrowsingCoordinator {
    private struct PeekPresentation: Equatable {
        let request: BrowserPeekRequest
        var phase: BrowserPeekPresentationPhase
        var motion: BrowserPeekMotionState?
    }

    private var peeks: [PeekPresentation] {
        get { observed(\.peeksStorage, as: \.peeks) }
        set { publish(newValue, into: \.peeksStorage, as: \.peeks) }
    }
    @ObservationIgnored private var peeksStorage = [PeekPresentation]()
    var peekRequests: [BrowserPeekRequest] { peeks.map(\.request) }
    var peekRequest: BrowserPeekRequest? { peeks.last?.request }
    private(set) var quickWindowRequest: BrowserQuickWindowRequest?

    func presentationPhase(for request: BrowserPeekRequest) -> BrowserPeekPresentationPhase? {
        peeks.first { $0.request == request }?.phase
    }

    func motionState(for request: BrowserPeekRequest) -> BrowserPeekMotionState? {
        peeks.first { $0.request == request }?.motion
    }

    func handleLinkDrag(_ event: any BrowserPeekInteractionEvent) {
        event.apply(to: self)
    }

    func presentPeek(_ request: BrowserPeekRequest) {
        beginPeekDrag(request, state: .opening(from: request.sourcePresentation))
        commitPeek(request)
    }

    func stagePeek(_ request: BrowserPeekRequest) {
        peeks.removeAll {
            $0.phase == .staged || $0.request.sourceTabID == request.sourceTabID || $0.request.id == request.id
        }
        peeks.append(PeekPresentation(request: request, phase: .staged))
        quickWindowRequest = nil
    }

    func commitPeek(_ request: BrowserPeekRequest) {
        guard let index = peeks.firstIndex(where: { $0.request == request && $0.phase == .staged }) else { return }
        peeks[index].phase = .committed
    }

    func cancelStagedPeek(id: UUID) {
        peeks.removeAll { $0.request.id == id && $0.phase == .staged }
    }

    func dismissPeek() {
        peeks.removeAll()
    }

    func beginPeekDrag(_ request: BrowserPeekRequest, state: BrowserPeekMotionState) {
        stagePeek(request)
        peeks[peeks.count - 1].motion = state
    }

    func updatePeekDrag(id: UUID, state: BrowserPeekMotionState) {
        guard let index = peeks.firstIndex(where: { $0.request.id == id && $0.phase == .staged }),
            peeks[index].motion != nil
        else { return }
        peeks[index].motion = state
        if state.releasedAt != nil && !state.returnsToSource { peeks[index].phase = .committed }
    }

    func isPresentingPeek(_ request: BrowserPeekRequest) -> Bool {
        peeks.contains { $0.request == request }
    }

    @discardableResult
    func dismissPeek(_ request: BrowserPeekRequest) -> Bool {
        guard isPresentingPeek(request) else { return false }
        peeks.removeAll { $0.request == request }
        return true
    }

    /// The Peeks whose source tab left its Space, as `browser` reads it.
    func orphanedPeeks(in browser: BrowserStore) -> [UUID] {
        peeks.filter { !$0.request.hasSource(in: browser) }.map(\.request.id)
    }

    /// Dismisses every Peek whose source tab left its Space.
    func reconcilePeeks(in browser: BrowserStore) {
        peeks.removeAll { !$0.request.hasSource(in: browser) }
    }

    func presentQuickWindow(_ request: BrowserQuickWindowRequest) {
        quickWindowRequest = request
        dismissPeek()
    }

    func dismissQuickWindow() {
        quickWindowRequest = nil
    }

    func isPresentingQuickWindow(_ request: BrowserQuickWindowRequest) -> Bool {
        guard let current = quickWindowRequest else { return false }
        return current.hasSamePresentationIdentity(as: request)
    }

    @discardableResult
    func dismissQuickWindow(_ request: BrowserQuickWindowRequest) -> Bool {
        guard isPresentingQuickWindow(request) else { return false }
        dismissQuickWindow()
        return true
    }
}

extension BrowserTransientBrowsingCoordinator: BrowserStoreFirstObservable {}
