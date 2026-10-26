import Foundation

/// A window owner's stable release-notes action. Rebuilding a view does not
/// change the environment action while its owning window service stays the same.
struct BrowserSoftwareUpdateDetailsAction: Equatable {
    // MARK: - Variables

    private let ownerID: ObjectIdentifier
    private let perform: @MainActor () -> Void

    // MARK: - Initializers

    init(owner: AnyObject, perform: @escaping @MainActor () -> Void) {
        ownerID = ObjectIdentifier(owner)
        self.perform = perform
    }

    // MARK: - Actions

    @MainActor func callAsFunction() { perform() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.ownerID == rhs.ownerID }
}
