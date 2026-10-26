import Foundation

/// Owns Peek requests and pull lifetimes after a platform claims a link gesture.
@MainActor
final class BrowserLinkPullHandler {
    private let context: () -> BrowserPageNavigationContext?
    private let handle: (any BrowserPeekInteractionEvent) -> Void
    private var interaction: Interaction?

    private struct Interaction {
        let request: BrowserPeekRequest
        var pull: BrowserPeekPullSession
    }

    init(
        context: @escaping () -> BrowserPageNavigationContext?,
        handle: @escaping (any BrowserPeekInteractionEvent) -> Void
    ) {
        self.context = context
        self.handle = handle
    }

    var isActive: Bool { interaction != nil }

    @discardableResult
    func begin(url: URL, label: String?, origin: CGPoint, sample: BrowserLinkPullSample) -> Bool {
        guard !isActive, sample.isValid, origin.x.isFinite, origin.y.isFinite,
            ExternalWebLink.accepts(url), let source = context()
        else { return false }
        let request = BrowserPeekRequest(
            url: url, sourceTabID: source.tabID, sourceTitle: source.title,
            spaceAssignment: source.assignment, trigger: .linkDrag,
            sourcePresentation: BrowserPeekSourcePresentation(
                normalizedMinX: origin.x, normalizedMinY: origin.y,
                normalizedWidth: 0, normalizedHeight: 0, label: label ?? source.title))
        let pull = BrowserPeekPullSession(
            origin: origin, location: sample.location, size: sample.size, time: sample.time)
        interaction = Interaction(request: request, pull: pull)
        handle(BrowserPeekDragBegan(request: request, state: pull.state))
        return true
    }

    func move(_ sample: BrowserLinkPullSample) {
        update(sample, isEnding: false)
    }

    func end(_ sample: BrowserLinkPullSample) {
        update(sample, isEnding: true)
    }

    @discardableResult
    func validateSource() -> Bool {
        guard let interaction else { return false }
        guard let source = context(),
            source.tabID == interaction.request.sourceTabID,
            source.assignment == interaction.request.assignment
        else {
            cancel()
            return false
        }
        return true
    }

    func cancel() {
        let requestID = interaction?.request.id
        interaction = nil
        if let requestID { handle(BrowserPeekDragCancelled(requestID: requestID)) }
    }

    private func update(_ sample: BrowserLinkPullSample, isEnding: Bool) {
        guard validateSource(), var current = interaction else { return }
        guard sample.isValid, !isEnding || sample.isInsideWindow else {
            cancel()
            return
        }
        current.pull.move(to: sample.location, size: sample.size, time: sample.time)
        if isEnding {
            current.pull.release(size: sample.size)
            interaction = nil
        } else {
            interaction = current
        }
        handle(BrowserPeekDragMoved(requestID: current.request.id, state: current.pull.state))
    }
}
