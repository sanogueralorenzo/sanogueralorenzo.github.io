import Foundation

/// Describes whether a transient request may retain a live page. A usable
/// request carries the Space of the read model its page opens in; each other
/// disposition settles its holder in its own way.
@MainActor
struct BrowserTransientLeaseDisposition: Equatable {
    // MARK: - Static Variables

    /// The request is no longer presented, so its page goes.
    static let notPresented = BrowserTransientLeaseDisposition(
        name: "notPresented", space: nil, settlesHolder: { $0.releaseLease() })
    /// The request's source left its Space, so the request goes.
    static let sourceMissing = BrowserTransientLeaseDisposition(
        name: "sourceMissing", space: nil, settlesHolder: { $0.dismissUnavailableRequest() })
    /// The request's Space is locked, so its page goes until it unlocks.
    static let sourceLocked = BrowserTransientLeaseDisposition(
        name: "sourceLocked", space: nil, settlesHolder: { $0.setSourceLocked(true) })

    // MARK: - Variables

    let name: String
    /// The Space of the read model the page opens in, while the page may be kept.
    let space: SpaceModel?
    private let settlesHolder: @MainActor (any BrowserTransientLeaseHolder) -> Void

    // MARK: - Initializers

    private init(
        name: String,
        space: SpaceModel?,
        settlesHolder: @escaping @MainActor (any BrowserTransientLeaseHolder) -> Void
    ) {
        self.name = name
        self.space = space
        self.settlesHolder = settlesHolder
    }

    /// The disposition of a request, answered in ladder order: presented,
    /// then its source, then its lock.
    init(
        isPresentingRequest: Bool,
        space: SpaceModel?,
        isLocked: @MainActor (SpaceModel) -> Bool
    ) {
        guard isPresentingRequest else {
            self = .notPresented
            return
        }
        guard let space else {
            self = .sourceMissing
            return
        }
        guard !isLocked(space) else {
            self = .sourceLocked
            return
        }
        self = .usable(space)
    }

    // MARK: - Actions - Settling

    static func usable(_ space: SpaceModel) -> BrowserTransientLeaseDisposition {
        BrowserTransientLeaseDisposition(name: "usable", space: space, settlesHolder: { _ in })
    }

    /// The Space the page may be kept in, or nil once `holder` has done what
    /// this disposition asks of a page it may not keep.
    @discardableResult
    func settle(on holder: some BrowserTransientLeaseHolder) -> SpaceModel? {
        guard let space else {
            settlesHolder(holder)
            return nil
        }
        return space
    }

    // MARK: - Actions - Identity

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.space === rhs.space
    }
}
