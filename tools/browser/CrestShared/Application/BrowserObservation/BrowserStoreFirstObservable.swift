/// An `@Observable` model that stores a value before announcing its change.
///
/// Observation announces a change before the new value is stored, and SwiftUI
/// can render during that announcement: when an earlier update from a
/// different transaction is still pending, it flushes that update on the spot.
/// A view rendered there reads the old value and consumes the change, so a
/// lone write that nothing redraws afterwards stays stale on screen — a
/// sidebar that will not close, a bar that will not open, an `onChange` that
/// never runs. State like that is kept in `@ObservationIgnored` storage and
/// published through ``publish(_:into:as:)``, so any such render reads the new
/// value.
///
/// The macro-generated `access(keyPath:)` and `withMutation(keyPath:_:)` of an
/// `@Observable` final class satisfy the requirements.
@MainActor
protocol BrowserStoreFirstObservable: AnyObject {
    func access<Member>(keyPath: KeyPath<Self, Member>)
    func withMutation<Member, MutationResult>(
        keyPath: KeyPath<Self, Member>,
        _ mutation: () throws -> MutationResult
    ) rethrows -> MutationResult
}

extension BrowserStoreFirstObservable {
    /// Reads `storage` while registering the read as one of `property`.
    func observed<Value>(
        _ storage: KeyPath<Self, Value>,
        as property: KeyPath<Self, Value>
    ) -> Value {
        access(keyPath: property)
        return self[keyPath: storage]
    }

    /// Stores `value` in `storage`, then announces a change to `property`.
    /// An equal value is neither stored nor announced.
    func publish<Value: Equatable>(
        _ value: Value,
        into storage: ReferenceWritableKeyPath<Self, Value>,
        as property: KeyPath<Self, Value>
    ) {
        guard self[keyPath: storage] != value else { return }
        self[keyPath: storage] = value
        withMutation(keyPath: property) {}
    }

    /// Stores `object` under `key` in the map `storage`, or removes the key
    /// when `object` is nil, then announces a change to `property`. The
    /// object the key already holds, or the removal of a key the map lacks,
    /// is neither stored nor announced.
    func publish<Key: Hashable, Object: AnyObject>(
        _ object: Object?,
        forKey key: Key,
        into storage: ReferenceWritableKeyPath<Self, [Key: Object]>,
        as property: KeyPath<Self, [Key: Object]>
    ) {
        guard self[keyPath: storage][key] !== object else { return }
        self[keyPath: storage][key] = object
        withMutation(keyPath: property) {}
    }
}
