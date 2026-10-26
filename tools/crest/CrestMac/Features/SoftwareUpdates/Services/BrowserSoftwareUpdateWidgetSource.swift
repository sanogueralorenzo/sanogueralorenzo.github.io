import Foundation

@MainActor
final class BrowserSoftwareUpdateWidgetSource:
    BrowserSidebarWidgetEventSource
{
    // MARK: - Variables

    let kindID = BrowserSidebarWidgetKindID.softwareUpdate

    private weak var model: BrowserSoftwareUpdateModel?
    private var currentInstance: BrowserSidebarWidgetInstance?
    private var subscribers: [UUID: AsyncStream<[BrowserSidebarWidgetInstance]>.Continuation] = [:]

    // MARK: - Actions - Publishing

    func bind(_ model: BrowserSoftwareUpdateModel) {
        self.model = model
        publish(model.sidebarWidgetSnapshot)
    }

    func publish(_ snapshot: BrowserSoftwareUpdateWidgetSnapshot?) {
        let next = snapshot.map(Self.instance(for:))
        guard next != currentInstance else { return }
        currentInstance = next
        let instances = next.map { [$0] } ?? []
        for continuation in subscribers.values {
            continuation.yield(instances)
        }
    }

    func events() -> AsyncStream<[BrowserSidebarWidgetInstance]> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream<[BrowserSidebarWidgetInstance]>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        subscribers[subscriberID] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                self?.subscribers.removeValue(forKey: subscriberID)
            }
        }
        continuation.yield(currentInstance.map { [$0] } ?? [])
        return stream
    }

    private static func instance(
        for snapshot: BrowserSoftwareUpdateWidgetSnapshot
    ) -> BrowserSidebarWidgetInstance {
        BrowserSidebarWidgetInstance(
            id: BrowserSidebarWidgetID(
                kindID: .softwareUpdate,
                instanceID: snapshot.build ?? snapshot.version ?? "available"
            ),
            scope: .application,
            orderingOrdinal: 0,
            presentation: .softwareUpdate(snapshot),
            availableActions: snapshot.phase.cardActions(for: snapshot)
        )
    }

    // MARK: - Actions - Card actions

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {
        guard instanceID == currentInstance?.id, let model else { return }
        action.perform(on: model)
    }
}
