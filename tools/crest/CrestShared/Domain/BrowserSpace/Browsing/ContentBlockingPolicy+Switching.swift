import Foundation

extension ContentBlockingPolicy {
    // MARK: - Actions - Switching

    /// The policy a Space's blocking switch moves to: one that blocks when this
    /// one blocks nothing, and one that blocks nothing when this one blocks.
    var switched: ContentBlockingPolicy {
        Self.all.first { $0.blocksContent != blocksContent } ?? self
    }

    /// What a page's actions offer for the selected Space's policy. Without a
    /// Space, they offer to turn blocking on.
    static func switchTitle(for policy: ContentBlockingPolicy?) -> LocalizedStringResource {
        (policy ?? .blocking(false)).switchTitle
    }

    /// The policy that blocks, or does not, as a switch asks.
    static func blocking(_ blocks: Bool) -> ContentBlockingPolicy {
        guard let policy = all.first(where: { $0.blocksContent == blocks }) else {
            preconditionFailure("The core offers a policy that blocks and one that does not.")
        }
        return policy
    }
}
