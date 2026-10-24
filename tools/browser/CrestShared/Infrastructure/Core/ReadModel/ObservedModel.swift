import Foundation

/// An object of the read model that holds one record of the core's model and
/// notifies only the observers of what really changes. The generator emits one
/// for each `[Observed]` contract record; `SpaceModel` is written by hand.
@MainActor
protocol ObservedModel: AnyObject {
    associatedtype Value

    /// The record the object holds now.
    var value: Value { get }

    init(_ value: Value)

    /// Takes the next value of the same record, assigning only what differs.
    func update(_ value: Value)
}
