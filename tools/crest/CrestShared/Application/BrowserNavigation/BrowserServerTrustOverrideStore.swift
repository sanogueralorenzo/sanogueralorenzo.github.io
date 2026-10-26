import Foundation

@MainActor
final class BrowserServerTrustOverrideStore {
    private struct Approval: Hashable {
        let profileID: UUID
        let identity: BrowserServerTrustIdentity
    }

    private var approvals: Set<Approval> = []

    func approve(_ identity: BrowserServerTrustIdentity, for profileID: UUID) {
        approvals.insert(Approval(profileID: profileID, identity: identity))
    }

    func isApproved(
        _ identity: BrowserServerTrustIdentity,
        for profileID: UUID
    ) -> Bool {
        approvals.contains(Approval(profileID: profileID, identity: identity))
    }

    func removeApprovals(for profileID: UUID) {
        approvals = Set(approvals.filter { $0.profileID != profileID })
    }
}
