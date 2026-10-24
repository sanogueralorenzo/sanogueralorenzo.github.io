import SwiftUI

extension EnvironmentValues {
    @Entry var spacePagerPresentation: SpacePagerPresentation? = nil
    /// Retained content can render before its Space owns input or focus.
    @Entry var spaceContentIsInteractive = true
}

/// A view-only connection between native page motion, backgrounds, and icons.
/// It deliberately does not participate in Observation: progress updates only
/// the native presentation leaf, never the browser selection or sidebar rows.
@MainActor
final class SpacePagerPresentation {
    enum Phase: Equatable {
        case idle
        case tracking
        case settling
    }

    struct Snapshot: Equatable {
        let generation: UInt
        let spaceIDs: [UUID]
        /// Fractional index in semantic Space order, independent of layout direction.
        let position: CGFloat
        let phase: Phase
        let destinationID: UUID?
        var transition: SpacePagerSettlement? = nil
    }

    private(set) var snapshot: Snapshot?
    /// Fixed controls above the moving page remain part of its gesture region.
    var gestureTopInset: CGFloat = 0
    private struct Observer {
        weak var owner: AnyObject?
        let receive: (Snapshot) -> Void
    }
    private var observers: [ObjectIdentifier: Observer] = [:]

    func publish(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        observers = observers.filter { $0.value.owner != nil }
        for observer in observers.values {
            if observer.owner != nil { observer.receive(snapshot) }
        }
    }

    func observe(owner: AnyObject, receive: @escaping (Snapshot) -> Void) {
        observers[ObjectIdentifier(owner)] = Observer(owner: owner, receive: receive)
        if let snapshot { receive(snapshot) }
    }

    func removeObserver(owner: AnyObject) {
        observers.removeValue(forKey: ObjectIdentifier(owner))
    }
}
