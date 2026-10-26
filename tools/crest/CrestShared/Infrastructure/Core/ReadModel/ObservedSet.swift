import Foundation
import Observation

/// A set whose membership is observed element by element. Reading whether it
/// holds one element observes only that element's slot, so a change notifies
/// only the readers of the elements that joined or left: a window showing
/// another tab redraws the two rows it concerns and no list, and a lookup in
/// an `ObservedList` redraws only when its own record joins or leaves. Each
/// slot stores its membership before it announces it; see
/// `BrowserStoreFirstObservable`.
@MainActor
final class ObservedSet<Element: Hashable> {
    // MARK: - Types

    /// Whether one element is a member, observed on its own.
    @MainActor
    @Observable
    fileprivate final class Slot: BrowserStoreFirstObservable {
        var isMember: Bool {
            get { observed(\.isMemberStorage, as: \.isMember) }
            set { publish(newValue, into: \.isMemberStorage, as: \.isMember) }
        }
        @ObservationIgnored private var isMemberStorage: Bool

        init(isMember: Bool) {
            isMemberStorage = isMember
        }
    }

    // MARK: - Variables

    /// The members. Reading them observes nothing.
    private(set) var members: Set<Element> = []
    /// A slot for each element that was read or joined, made the first time
    /// either happens, so a reader hears when an element it read joins later.
    private var slots: [Element: Slot] = [:]

    // MARK: - Initializers

    init(_ members: Set<Element> = []) {
        self.members = members
    }

    // MARK: - Actions - Reading

    /// Whether the set holds `element`. Reading it observes only whether
    /// `element` joins or leaves, and answers from the stored membership, so
    /// a reader told of one element's change reads every other one's too.
    func contains(_ element: Element) -> Bool {
        _ = slot(element).isMember
        return members.contains(element)
    }

    // MARK: - Actions - Changes

    func insert(_ element: Element) {
        update(joining: [element], leaving: [])
    }

    func remove(_ element: Element) {
        update(joining: [], leaving: [element])
    }

    /// Takes a whole new membership, announcing only the elements that joined
    /// or left.
    func replace(with newMembers: Set<Element>) {
        update(joining: newMembers.subtracting(members), leaving: members.subtracting(newMembers))
    }

    /// The `joining` elements join and the `leaving` ones leave; one named in
    /// both ends up a member. Every membership is stored before any is
    /// announced, and only an element whose membership changes is announced.
    func update(joining: some Sequence<Element>, leaving: some Sequence<Element>) {
        let joining = Set(joining)
        var announced: [(slot: Slot, isMember: Bool)] = []
        for element in leaving where !joining.contains(element) && members.remove(element) != nil {
            if let slot = slots[element] { announced.append((slot, false)) }
        }
        for element in joining where members.insert(element).inserted {
            if let slot = slots[element] { announced.append((slot, true)) }
        }
        for (slot, isMember) in announced { slot.isMember = isMember }
    }

    private func slot(_ element: Element) -> Slot {
        if let slot = slots[element] { return slot }
        let slot = Slot(isMember: members.contains(element))
        slots[element] = slot
        return slot
    }
}
