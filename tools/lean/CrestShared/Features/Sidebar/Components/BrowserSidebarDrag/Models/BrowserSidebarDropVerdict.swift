import Foundation

/// What the core says of one drop: it may land, a rule refuses it, or the
/// core offers no such target for the lift.
struct BrowserSidebarDropVerdict: Equatable, Sendable {
    // MARK: - Static Variables

    static let allowed = Self(refusal: nil, isOffered: true)
    static let unavailable = Self(refusal: nil, isOffered: false)

    // MARK: - Variables

    /// The rule that refuses the drop, if one does.
    let refusal: Rejection?
    /// Whether the core lists the target for the lift at all.
    let isOffered: Bool

    /// What the person is told of a refused drop, in the refusal's own words.
    var constraintMessage: String? {
        refusal?.placementExplanation
    }

    // MARK: - Initializers

    private init(refusal: Rejection?, isOffered: Bool) {
        self.refusal = refusal
        self.isOffered = isOffered
    }

    /// A target the core listed, refused by `refusal` or allowed; a target it
    /// did not list, unavailable.
    init(_ listed: Rejection??) {
        self.init(refusal: listed ?? nil, isOffered: listed != nil)
    }

    // MARK: - Actions - Targets

    static func refused(_ refusal: Rejection) -> Self {
        Self(refusal: refusal, isOffered: true)
    }
}
