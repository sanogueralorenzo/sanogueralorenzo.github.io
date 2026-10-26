import Foundation
import Observation

/// An ordered list of read-model objects, one per record identity. A change
/// updates the object that holds a record in place, so only the observers of
/// the fields that changed hear of it. The list itself announces two things
/// apart: each record's membership, when that record joins or leaves, and its
/// order, which `models` reads and which a membership change also changes. A
/// lookup observes only its own record's membership, so a tab that opens or
/// closes never redraws a view that looked up another. Each is stored before
/// it is announced, so a view that renders during the announcement reads the
/// new list; see `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class ObservedList<Model: ObservedModel & Identifiable>
where Model.ID == UUID, Model.Value: Identifiable, Model.Value.ID == UUID {
    // MARK: - Variables

    /// The objects, in order. Reading them observes the list's order and
    /// membership.
    var models: [Model] {
        access(keyPath: \.models)
        return modelsStorage
    }
    @ObservationIgnored private var modelsStorage: [Model] = []
    /// The objects by identity, observed by no one.
    @ObservationIgnored private var byID: [UUID: Model] = [:]
    /// Which records the list holds, each observed on its own.
    private let membership = ObservedSet<UUID>()

    /// The records, in order. Reading them observes every field of every object.
    var values: [Model.Value] { models.map(\.value) }

    // MARK: - Initializers

    init(_ values: [Model.Value]) {
        replace(with: values)
    }

    // MARK: - Actions - Reading

    /// The object that holds the record with this identity, or nil when the
    /// list holds none. Reading it observes only whether that record joins or
    /// leaves: neither the list's order nor any other record's membership.
    func model(_ id: UUID) -> Model? {
        membership.contains(id) ? byID[id] : nil
    }

    func contains(_ id: UUID) -> Bool {
        model(id) != nil
    }

    // MARK: - Actions - Changes

    /// Applies one change the way the core's list changes read: the `removed`
    /// records are gone, each `updated` record replaces the one with its
    /// identity where it stands or goes after the others when it is new, and
    /// `order`, when present, names every record in its new order. The list
    /// stores its new order and membership before it announces either.
    func apply(updated: [Model.Value], removed: [UUID], order: [UUID]?) {
        var next = modelsStorage
        var held = byID
        var joined: [UUID] = []
        var left: [UUID] = []
        var isRearranged = false
        if !removed.isEmpty {
            let gone = Set(removed)
            if next.contains(where: { gone.contains($0.id) }) {
                next.removeAll { gone.contains($0.id) }
                isRearranged = true
            }
            for id in removed where held.removeValue(forKey: id) != nil { left.append(id) }
        }
        for value in updated {
            if let model = held[value.id] {
                model.update(value)
            } else {
                let model = Model(value)
                held[value.id] = model
                next.append(model)
                joined.append(value.id)
                isRearranged = true
            }
        }
        if let order {
            let ordered = order.compactMap { held[$0] }
            if !ordered.elementsEqual(next, by: ===) {
                let kept = Set(order)
                for model in next where !kept.contains(model.id) {
                    held[model.id] = nil
                    left.append(model.id)
                }
                next = ordered
                isRearranged = true
            }
        }
        byID = held
        if isRearranged { modelsStorage = next }
        membership.update(joining: joined, leaving: left)
        if isRearranged { withMutation(keyPath: \.models) {} }
    }

    /// Takes a whole new list, keeping the object of every record it still holds.
    func replace(with values: [Model.Value]) {
        let kept = Set(values.map(\.id))
        apply(
            updated: values, removed: modelsStorage.map(\.id).filter { !kept.contains($0) },
            order: values.map(\.id))
    }
}
