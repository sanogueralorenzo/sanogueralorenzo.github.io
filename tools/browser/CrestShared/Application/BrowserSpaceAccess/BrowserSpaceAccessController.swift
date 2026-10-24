import Foundation
import Observation

/// The app's one Space access controller. The core keeps the grants and the
/// request waiting on the device owner; this controller presents the system's
/// authentication prompt and answers the core with its result, and views read
/// each Space's lock from the core's published access.
@Observable
@MainActor
final class BrowserSpaceAccessController {
    // MARK: - Types

    private struct WeakStore {
        weak var value: BrowserStore?
    }

    // MARK: - Variables

    private(set) var failure: BrowserSpaceAccessFailure?

    /// Tells the person, at the top of the window they are looking at, about a
    /// change to a Space's access that could not happen. The platform supplies
    /// it where it has such a place.
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?

    @ObservationIgnored private let authenticator: any BrowserDeviceAuthenticating
    /// The core whose grants these are, once a store is attached.
    @ObservationIgnored private var core: CrestCore?
    /// The stores whose workspaces show the Spaces this controller unlocks.
    @ObservationIgnored private var stores: [WeakStore] = []

    /// The Space profile whose unlock is waiting on the device owner.
    var authenticatingAssignment: BrowserSpaceRuntimeAssignment? {
        core?.state.spaceAccess.first { $0.value.isAuthenticating }?.key
    }

    // MARK: - Initializers

    init(
        authenticator: any BrowserDeviceAuthenticating = SystemBrowserDeviceAuthenticator()
    ) {
        self.authenticator = authenticator
    }

    // MARK: - Actions - Stores

    /// Unlocks Spaces the workspace of `store` shows, through its core.
    func attach(_ store: BrowserStore) {
        core = store.core
        stores.removeAll { $0.value == nil || $0.value === store }
        stores.append(WeakStore(value: store))
    }

    // MARK: - Actions - Access

    /// A Space of the read model that asks for authentication shows only
    /// while this process holds the grant for its profile.
    func isLocked(_ space: SpaceModel) -> Bool {
        guard space.settings.requiresAuthentication else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        return core?.state.spaceAccess[assignment]?.isUnlocked != true
    }

    /// Whether a Space, as its identity views draw it, shows only once this
    /// process holds the grant for its profile.
    func isLocked(_ space: BrowserSpaceIdentity) -> Bool {
        guard space.requiresAuthentication else { return false }
        return core?.state.spaceAccess[space.assignment]?.isUnlocked != true
    }

    func isAuthenticating(_ space: BrowserSpaceIdentity) -> Bool {
        isAuthenticating(space.assignment)
    }

    func isAuthenticating(_ space: SpaceModel) -> Bool {
        isAuthenticating(BrowserSpaceRuntimeAssignment(space: space))
    }

    private func isAuthenticating(_ assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        core?.state.spaceAccess[assignment]?.isAuthenticating == true
    }

    /// Authentication authorizes one profile identity. A window may replace or
    /// delete that profile while the system prompt is awaiting a response. A
    /// change the core refuses is announced, and the Space keeps the access
    /// the core holds.
    @discardableResult
    func updatePolicy(
        _ policy: SpaceAccessPolicy,
        matching assignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore
    ) async -> Bool {
        guard let space = browser.spaceModel(matching: assignment) else { return false }
        if policy == .open {
            guard await unlock(space) else { return false }
        }
        guard browser.spaceModel(matching: assignment) != nil else { return false }
        guard browser.updateSpaceAccessPolicy(policy, in: assignment.spaceID) == nil else {
            announce?(String(localized: "Couldn’t change the lock on “\(space.settings.name)”"))
            return false
        }
        if policy != .open {
            lock(assignment.spaceID)
        }
        return true
    }

    /// Asks the device owner to unlock a Space of the read model, answering
    /// whether it is unlocked afterwards. One request waits at a time; only
    /// its own answer can unlock the Space, so a lock while the prompt is up
    /// keeps it locked.
    @discardableResult
    func unlock(_ space: SpaceModel) async -> Bool {
        guard isLocked(space) else { return true }
        return await unlock(BrowserSpaceRuntimeAssignment(space: space), named: space.settings.name)
    }

    /// Asks the device owner to unlock a Space its identity views draw.
    @discardableResult
    func unlock(_ space: BrowserSpaceIdentity) async -> Bool {
        guard isLocked(space) else { return true }
        return await unlock(space.assignment, named: space.name)
    }

    /// Unlocks the locked Space profile `assignment` names.
    private func unlock(_ assignment: BrowserSpaceRuntimeAssignment, named name: String) async -> Bool {
        guard let core, let workspace = workspace(showing: assignment) else {
            failure = .authenticationUnavailable
            return false
        }
        let space = assignment.spaceID
        let request = UUID()
        do throws(Rejection) {
            try core.send(BeginUnlockingSpace(workspaceID: workspace, spaceID: space, requestID: request))
        } catch {
            if case .authenticationBusy = error { return false }
            failure = .authenticationUnavailable
            return false
        }
        guard isAuthenticating(assignment) else { return core.state.spaceAccess[assignment]?.isUnlocked == true }
        failure = nil
        do {
            let authenticated = try await authenticator.authenticate(
                reason: String(
                    localized: "Authenticate to unlock the \(name) Space in Crest."
                )
            )
            guard finish(request, for: space, authenticated: authenticated) else {
                if authenticated { announce?(String(localized: "“\(name)” locked again. Try again.")) }
                return false
            }
            guard authenticated else {
                failure = .authenticationDenied
                return false
            }
            return true
        } catch {
            guard finish(request, for: space, authenticated: false) else { return false }
            failure = .authenticationUnavailable
            return false
        }
    }

    func lock(_ spaceID: UUID) {
        _ = try? core?.send(LockSpace(spaceID: spaceID))
    }

    /// The scene went inactive, which the system's own authentication prompt
    /// also causes: while an unlock waits on it, nothing locks.
    func lockAllForInactiveScene() {
        _ = try? core?.send(LockAllSpaces(sceneWentInactive: true))
    }

    func lockAll() {
        _ = try? core?.send(LockAllSpaces(sceneWentInactive: false))
    }

    /// Answers the core's waiting request, and whether it was still the one
    /// waiting.
    private func finish(_ request: UUID, for spaceID: UUID, authenticated: Bool) -> Bool {
        (try? core?.send(
            FinishUnlockingSpace(spaceID: spaceID, requestID: request, authenticated: authenticated))) != nil
    }

    /// The workspace of an attached store that shows the Space profile.
    private func workspace(showing assignment: BrowserSpaceRuntimeAssignment) -> UUID? {
        stores.compactMap(\.value).first { $0.spaceModel(matching: assignment) != nil }?.family.workspaceID
    }
}
