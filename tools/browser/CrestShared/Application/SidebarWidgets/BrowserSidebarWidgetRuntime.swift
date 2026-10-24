import Foundation
import Observation

@MainActor
protocol BrowserSidebarWidgetEventSource: AnyObject {
    var kindID: BrowserSidebarWidgetKindID { get }

    /// A source retains authoritative state independently of this stream. Every
    /// subscription first yields that state, then keeps only the newest pending
    /// update so a suspended sidebar cannot accumulate an unbounded queue.
    func events() -> AsyncStream<[BrowserSidebarWidgetInstance]>

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    )
}

struct BrowserSidebarWidgetHostRegistration: Equatable, Sendable {
    let platform: BrowserSidebarWidgetPlatform
    let capabilities: BrowserSidebarWidgetCapabilities
    let isActive: Bool
}

@Observable
@MainActor
final class BrowserSidebarWidgetRuntime: BrowserSidebarWidgetPreferenceObserving {
    let registry: BrowserSidebarWidgetRegistry

    private(set) var publishedInstances: [BrowserSidebarWidgetInstance] = []
    private(set) var visibilityRevision = 0
    private(set) var disabledKindIdentifiers: Set<String>
    /// One deck, one centred card, shared by every Space of every profile.
    private(set) var carouselSelection: BrowserSidebarWidgetID?

    @ObservationIgnored private let sourcesByKindID: [BrowserSidebarWidgetKindID: any BrowserSidebarWidgetEventSource]
    @ObservationIgnored private let preferences: BrowserSidebarWidgetPreferenceStore
    @ObservationIgnored private var hosts: [UUID: BrowserSidebarWidgetHostRegistration] = [:]
    @ObservationIgnored private var workerTasks: [BrowserSidebarWidgetKindID: Task<Void, Never>] = [:]
    @ObservationIgnored private var instancesByKindID: [BrowserSidebarWidgetKindID: [BrowserSidebarWidgetInstance]] =
        [:]
    @ObservationIgnored private var insertionOrdinalByInstanceID: [BrowserSidebarWidgetID: UInt64] = [:]
    @ObservationIgnored private var lastAutomaticInsertionOrdinal: UInt64 = 0
    @ObservationIgnored private var nextInsertionOrdinal: UInt64 = 0

    init(
        registrations: [BrowserSidebarWidgetRegistration],
        sources: [any BrowserSidebarWidgetEventSource],
        preferences: BrowserSidebarWidgetPreferenceStore = .shared
    ) {
        registry = BrowserSidebarWidgetRegistry(registrations: registrations)
        self.preferences = preferences
        disabledKindIdentifiers = preferences.disabledKindIdentifiers
        var uniqueSources: [BrowserSidebarWidgetKindID: any BrowserSidebarWidgetEventSource] = [:]
        for source in sources {
            precondition(
                uniqueSources[source.kindID] == nil,
                "A sidebar widget kind may own only one background source."
            )
            precondition(
                registry.registration(for: source.kindID) != nil,
                "Every sidebar widget source must have a registration."
            )
            uniqueSources[source.kindID] = source
        }
        sourcesByKindID = uniqueSources
        preferences.register(self)
    }

    deinit {
        for task in workerTasks.values { task.cancel() }
    }

    func activateHost(
        id: UUID,
        platform: BrowserSidebarWidgetPlatform = .current,
        capabilities: BrowserSidebarWidgetCapabilities
    ) {
        let next = BrowserSidebarWidgetHostRegistration(
            platform: platform,
            capabilities: capabilities,
            isActive: true
        )
        guard hosts[id] != next else { return }
        hosts[id] = next
        reconcileWorkers()
    }

    func suspendHost(id: UUID) {
        guard let current = hosts[id], current.isActive else { return }
        hosts[id] = BrowserSidebarWidgetHostRegistration(
            platform: current.platform,
            capabilities: current.capabilities,
            isActive: false
        )
        reconcileWorkers()
    }

    func removeHost(id: UUID) {
        guard hosts.removeValue(forKey: id) != nil else { return }
        reconcileWorkers()
    }

    func instances(
        platform: BrowserSidebarWidgetPlatform = .current,
        capabilities: BrowserSidebarWidgetCapabilities
    ) -> [BrowserSidebarWidgetInstance] {
        registry.visibleInstances(
            from: publishedInstances,
            platform: platform,
            capabilities: capabilities,
            disabledKindIdentifiers: disabledKindIdentifiers
        )
    }

    func userControllableRegistrations(
        platform: BrowserSidebarWidgetPlatform = .current
    ) -> [BrowserSidebarWidgetRegistration] {
        registry.userControllableRegistrations(platform: platform)
    }

    func isWidgetEnabled(_ kindID: BrowserSidebarWidgetKindID) -> Bool {
        guard let registration = registry.registration(for: kindID) else {
            return true
        }
        return registry.isEnabled(
            registration,
            disabledKindIdentifiers: disabledKindIdentifiers
        )
    }

    func setWidgetEnabled(
        _ isEnabled: Bool,
        for kindID: BrowserSidebarWidgetKindID
    ) {
        guard
            registry.registration(for: kindID)?.visibility.isUserControllable
                == true
        else { return }
        preferences.setEnabled(isEnabled, for: kindID)
    }

    func sidebarWidgetPreferencesDidChange() {
        disabledKindIdentifiers = preferences.disabledKindIdentifiers
        for registration in registry.registrations
        where !registry.isEnabled(
            registration,
            disabledKindIdentifiers: disabledKindIdentifiers
        ) {
            storeInstances([], for: registration.id)
        }
        reconcileCarouselSelection(visibleInstances: publishedInstances)
        reconcileWorkers()
    }

    func perform(
        _ action: BrowserSidebarWidgetAction,
        on instanceID: BrowserSidebarWidgetID
    ) {
        sourcesByKindID[instanceID.kindID]?.perform(
            action,
            on: instanceID
        )
    }

    func reconcileCarouselSelection(
        visibleInstances: [BrowserSidebarWidgetInstance]
    ) {
        guard !visibleInstances.isEmpty else {
            setCarouselSelection(nil)
            return
        }

        let latestID = mostRecentlyInsertedID(in: visibleInstances)
        let latestOrdinal = latestID.flatMap { insertionOrdinalByInstanceID[$0] } ?? 0
        let currentIsVisible = visibleInstances.contains {
            $0.id == carouselSelection
        }

        if latestOrdinal > lastAutomaticInsertionOrdinal {
            lastAutomaticInsertionOrdinal = latestOrdinal
            setCarouselSelection(latestID)
        } else if !currentIsVisible {
            setCarouselSelection(latestID ?? visibleInstances.first?.id)
        }
    }

    private func mostRecentlyInsertedID(
        in instances: [BrowserSidebarWidgetInstance]
    ) -> BrowserSidebarWidgetID? {
        instances.max { lhs, rhs in
            let lhsOrdinal = insertionOrdinalByInstanceID[lhs.id] ?? 0
            let rhsOrdinal = insertionOrdinalByInstanceID[rhs.id] ?? 0
            if lhsOrdinal != rhsOrdinal {
                return lhsOrdinal < rhsOrdinal
            }
            return lhs.id.id < rhs.id.id
        }?.id
    }

    func selectCarouselInstance(
        _ instanceID: BrowserSidebarWidgetID,
        visibleInstances: [BrowserSidebarWidgetInstance]
    ) {
        guard visibleInstances.contains(where: { $0.id == instanceID }) else {
            return
        }
        setCarouselSelection(instanceID)
    }

    func isWorkerRunning(for kindID: BrowserSidebarWidgetKindID) -> Bool {
        workerTasks[kindID] != nil
    }

    private func reconcileWorkers() {
        for registration in registry.registrations {
            guard let source = sourcesByKindID[registration.id] else {
                continue
            }
            let shouldRun = hosts.values.contains { host in
                host.isActive
                    && registry.isEnabled(
                        registration,
                        disabledKindIdentifiers: disabledKindIdentifiers
                    )
                    && registry.supports(
                        registration,
                        platform: host.platform,
                        capabilities: host.capabilities
                    )
            }
            if shouldRun, workerTasks[registration.id] == nil {
                startWorker(for: registration.id, source: source)
            } else if !shouldRun,
                let task = workerTasks.removeValue(forKey: registration.id)
            {
                task.cancel()
            }
        }
    }

    private func startWorker(
        for kindID: BrowserSidebarWidgetKindID,
        source: any BrowserSidebarWidgetEventSource
    ) {
        let stream = source.events()
        workerTasks[kindID] = Task { @MainActor [weak self] in
            for await instances in stream {
                guard !Task.isCancelled else { return }
                self?.replaceInstances(for: kindID, with: instances)
            }
        }
    }

    private func replaceInstances(
        for kindID: BrowserSidebarWidgetKindID,
        with candidates: [BrowserSidebarWidgetInstance]
    ) {
        guard let registration = registry.registration(for: kindID) else {
            return
        }
        guard
            registry.isEnabled(
                registration,
                disabledKindIdentifiers: disabledKindIdentifiers
            )
        else {
            return
        }
        let matching = candidates.filter { $0.id.kindID == kindID }
        storeInstances(registration.instanceLimit.normalize(matching), for: kindID)
    }

    private func storeInstances(
        _ instances: [BrowserSidebarWidgetInstance],
        for kindID: BrowserSidebarWidgetKindID
    ) {
        guard instancesByKindID[kindID] != instances else { return }
        instancesByKindID[kindID] = instances
        let next = registry.registrations.flatMap {
            instancesByKindID[$0.id] ?? []
        }
        guard next != publishedInstances else { return }
        let previousIDs = Set(publishedInstances.map(\.id))
        let nextIDs = Set(next.map(\.id))
        let addedInstances =
            next
            .filter { !previousIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.orderingOrdinal != rhs.orderingOrdinal {
                    return lhs.orderingOrdinal < rhs.orderingOrdinal
                }
                return lhs.id.id < rhs.id.id
            }
        for instance in addedInstances {
            nextInsertionOrdinal &+= 1
            insertionOrdinalByInstanceID[instance.id] = nextInsertionOrdinal
        }
        insertionOrdinalByInstanceID = insertionOrdinalByInstanceID.filter {
            nextIDs.contains($0.key)
        }
        if let carouselSelection, !nextIDs.contains(carouselSelection) {
            self.carouselSelection = nil
        }
        publishedInstances = next
        visibilityRevision &+= 1
    }

    private func setCarouselSelection(
        _ instanceID: BrowserSidebarWidgetID?
    ) {
        guard carouselSelection != instanceID else { return }
        carouselSelection = instanceID
    }
}
