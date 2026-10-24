import Foundation

/// The platform's side of this device's link preferences.
///
/// The core owns them: the device store keeps them, the core applies every
/// edit and its rules, answers how a link a page's engine asks about opens,
/// forgets a deleted Space in them, and routes a link another app hands a
/// window. This store reads them from the read model and sends the person's
/// changes as intents. Each window keeps one over its core.
@MainActor
final class BrowserLinkPreferenceStore {
    // MARK: - Static Variables

    private static let log = DiagnosticLog.links

    // MARK: - Variables

    private let core: CrestCore

    /// The preferences as the core last published them.
    var preferences: LinkPreferences {
        guard let preferences = core.state.linkPreferences else {
            preconditionFailure("The core publishes the link preferences when the store adopts them.")
        }
        return preferences
    }

    // MARK: - Initializers

    /// A store over `core`, which has the core publish the preferences when
    /// it has not yet.
    init(core: CrestCore) {
        self.core = core
        if core.state.linkPreferences == nil { Self.adopt(nil, into: core) }
    }

    // MARK: - Actions - Adoption

    /// Carries the preferences an installed release kept under
    /// `crest.link-preferences.v1`, `legacyPreferences`, into `core`'s device
    /// store once; the core publishes them either way. A launch does this
    /// before any window opens.
    static func adopt(_ legacyPreferences: Data?, into core: CrestCore) {
        do {
            try core.send(AdoptLinkPreferences(preferences: legacyPreferences))
        } catch {
            preconditionFailure("The core refused to adopt the link preferences: \(error). Rebuild the core.")
        }
    }

    /// A store over a memory-only core of its own, as previews and tests
    /// use, which keeps nothing.
    convenience init() {
        self.init(core: CrestCore())
    }

    // MARK: - Actions - Changes

    func setBehavior(_ behavior: LinkBehavior, isOn: Bool) {
        send(SetLinkBehavior(behavior: behavior, isOn: isOn))
    }

    /// Where a link from another app opens when no route takes it; `spaceID`
    /// names the Space a destination that asks for one opens, and nil keeps
    /// the one chosen before.
    func chooseExternalDestination(_ destination: ExternalLinkDestination, spaceID: UUID? = nil) {
        send(ChooseExternalLinkDestination(destination: destination, spaceID: spaceID))
    }

    func choosePeekModifier(_ modifier: LinkPeekModifier) {
        send(ChoosePeekModifier(modifier: modifier))
    }

    func chooseArchivePolicy(_ policy: QuickWindowArchivePolicy) {
        send(ChooseQuickWindowArchivePolicy(policy: policy))
    }

    func addRoute(destinationSpaceID: UUID) {
        send(AddLinkRoute(routeID: UUID(), destinationSpaceID: destinationSpaceID))
    }

    func updateRoute(_ id: UUID, field: BrowserLinkRouteFieldUpdate) {
        send(field.edit(of: id))
    }

    func removeRoute(_ id: UUID) {
        send(RemoveLinkRoute(routeID: id))
    }

    func moveRoute(_ id: UUID, by offset: Int) {
        send(MoveLinkRoute(routeID: id, offset: offset))
    }

    /// Sends an edit; one the core refuses leaves the preferences as they were.
    private func send(_ intent: some LinkIntent) {
        do {
            try core.send(intent)
        } catch {
            Self.log.error(
                "The core refused \(String(describing: type(of: intent))): \(DiagnosticLog.describe(error))"
            )
        }
    }
}
