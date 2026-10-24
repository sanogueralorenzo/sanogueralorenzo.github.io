import Foundation

struct BrowserSidebarWidgetRegistry: Sendable {
    private let registrationsByID: [BrowserSidebarWidgetKindID: BrowserSidebarWidgetRegistration]

    init(registrations: [BrowserSidebarWidgetRegistration]) {
        var unique: [BrowserSidebarWidgetKindID: BrowserSidebarWidgetRegistration] = [:]
        for registration in registrations {
            precondition(
                unique[registration.id] == nil,
                "Sidebar widget kinds must have unique stable identifiers."
            )
            unique[registration.id] = registration
        }
        registrationsByID = unique
    }

    var registrations: [BrowserSidebarWidgetRegistration] {
        registrationsByID.values.sorted(by: Self.registrationPrecedes)
    }

    func registration(
        for kindID: BrowserSidebarWidgetKindID
    ) -> BrowserSidebarWidgetRegistration? {
        registrationsByID[kindID]
    }

    func supports(
        _ registration: BrowserSidebarWidgetRegistration,
        platform: BrowserSidebarWidgetPlatform,
        capabilities: BrowserSidebarWidgetCapabilities
    ) -> Bool {
        !registration.platforms.intersection(platform).isEmpty
            && capabilities.isSuperset(
                of: registration.requiredCapabilities
            )
    }

    func userControllableRegistrations(
        platform: BrowserSidebarWidgetPlatform
    ) -> [BrowserSidebarWidgetRegistration] {
        registrations.filter { registration in
            registration.visibility.isUserControllable
                && !registration.platforms.intersection(platform).isEmpty
        }
    }

    func isEnabled(
        _ registration: BrowserSidebarWidgetRegistration,
        disabledKindIdentifiers: Set<String>
    ) -> Bool {
        registration.visibility.isEnabled(
            registration.id,
            disabledKindIdentifiers: disabledKindIdentifiers
        )
    }

    /// The deck is one global layer, so visibility answers only what this build
    /// can render: the platform, the shell's capabilities, and each kind's
    /// instance policy. Profile and Space never enter the decision.
    func visibleInstances(
        from instances: [BrowserSidebarWidgetInstance],
        platform: BrowserSidebarWidgetPlatform,
        capabilities: BrowserSidebarWidgetCapabilities,
        disabledKindIdentifiers: Set<String> = []
    ) -> [BrowserSidebarWidgetInstance] {
        let eligible = instances.filter { instance in
            guard let registration = registrationsByID[instance.id.kindID]
            else { return false }
            return supports(
                registration,
                platform: platform,
                capabilities: capabilities
            )
                && isEnabled(
                    registration,
                    disabledKindIdentifiers: disabledKindIdentifiers
                )
        }

        var seenSingleKinds: Set<BrowserSidebarWidgetKindID> = []
        return eligible.sorted(by: instancePrecedes).filter { instance in
            guard registrationsByID[instance.id.kindID]?.instanceLimit.isSingle == true
            else { return true }
            return seenSingleKinds.insert(instance.id.kindID).inserted
        }
    }

    private static func registrationPrecedes(
        _ lhs: BrowserSidebarWidgetRegistration,
        _ rhs: BrowserSidebarWidgetRegistration
    ) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private func instancePrecedes(
        _ lhs: BrowserSidebarWidgetInstance,
        _ rhs: BrowserSidebarWidgetInstance
    ) -> Bool {
        let lhsRegistration = registrationsByID[lhs.id.kindID]
        let rhsRegistration = registrationsByID[rhs.id.kindID]
        if lhsRegistration?.order != rhsRegistration?.order {
            return (lhsRegistration?.order ?? .max)
                < (rhsRegistration?.order ?? .max)
        }
        if lhs.orderingOrdinal != rhs.orderingOrdinal {
            return lhs.orderingOrdinal < rhs.orderingOrdinal
        }
        return lhs.id.id < rhs.id.id
    }
}

extension BrowserSidebarWidgetCapabilities {
    fileprivate func isSuperset(of other: Self) -> Bool {
        intersection(other) == other
    }
}
