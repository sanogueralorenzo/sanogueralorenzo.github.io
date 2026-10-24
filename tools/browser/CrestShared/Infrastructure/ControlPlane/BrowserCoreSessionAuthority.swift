import Foundation
import Observation

/// One workspace the core opened for a store family. It holds no browsing
/// data: the read model holds the workspace's session, and only the session
/// changes the core publishes update it, so it can never show an unaccepted
/// edit. What each window shows is the core device's: an intent names the
/// window that issued it, and the device moves that window when the intent
/// commits and repairs the others.
///
/// The core opens the workspace (`OpenWorkspace`, `BorrowSpace`), gives it its
/// identity and closes it (`CloseWorkspace`). Whoever owns the family closes
/// it when its windows go; a workspace no one closed closes once this
/// authority is gone.
@Observable @MainActor
final class BrowserCoreSessionAuthority {
    // MARK: - Variables

    /// Whether the core still holds the workspace open. It closes when this
    /// authority closes it, when the workspace it borrows from closes or
    /// stops lending its Space, and when the core closes it for any other
    /// reason.
    var isOpen: Bool { device?.state.workspaces[workspaceID] != nil }
    /// The workspace the core gave the session, which every change to it names.
    let workspaceID: UUID
    /// The core whose device shows this session in its windows.
    @ObservationIgnored private(set) weak var device: CrestCore?

    // MARK: - Initializers

    /// The workspace `opened` announced.
    private init(opened: WorkspaceOpened, core: CrestCore) {
        workspaceID = opened.workspaceID
        device = core
    }

    /// A workspace no one closed closes on the main queue's next turn, never
    /// inside this deinit, which may run while the core applies a batch. It
    /// is skipped once the core is gone.
    isolated deinit {
        guard isOpen, let device else { return }
        let closing = CloseWorkspace(workspaceID: workspaceID)
        DispatchQueue.main.async { [weak device] in
            MainActor.assumeIsolated { _ = try? device?.send(closing) }
        }
    }

    // MARK: - Actions - Opening

    /// Opens a workspace of `kind` in `core`. With `seed`, a session a
    /// platform builds for a launch without a file (an isolated run, a preview
    /// or a test), it keeps nothing: it is never saved or synced, and each of
    /// its tabs wears the image `images` holds for the seed's tab. Without one,
    /// a private workspace starts from the core's private template. Throws the
    /// rule that refuses it.
    static func open(_ kind: WorkspaceKind, seed: SessionState.Seed?, images: [UUID: Data] = [:], in core: CrestCore)
        throws -> BrowserCoreSessionAuthority
    {
        try open(kind, seed: seed, in: core) { opened in
            guard let seed else { return [:] }
            var placed = images
            for (space, seeded) in zip(opened.spaces, seed.spaces) {
                for (tab, source) in zip(space.tabs, seeded.tabs) { placed[tab.id] = images[source.id] }
            }
            return placed
        }
    }

    /// Opens a workspace of `kind` from `seed`, whose tabs wear the images
    /// `images` places on the session the core opened. The core's repair
    /// keeps every Space and tab in its place, so a tab wears the image of the
    /// seed's tab in its place, even when the repair gave it a new identity
    /// because another tab shared its own.
    private static func open(
        _ kind: WorkspaceKind, seed: SessionState.Seed?, in core: CrestCore, images: (SessionState) -> [UUID: Data]
    ) throws -> BrowserCoreSessionAuthority {
        let opened = Self.opened(by: try core.send(OpenWorkspace(kind: kind, seed: seed)))
        if seed != nil { core.state.adoptImages(images(opened.session), in: opened.workspaceID) }
        return BrowserCoreSessionAuthority(opened: opened, core: core)
    }

    /// Opens the session `core` keeps in its file, as it loaded and repaired
    /// it. Each tab wears the image `favicons` keeps for it, and a tab the
    /// repair gave a new identity wears its source's. Throws `NoStoredSession`
    /// while the file holds no session yet.
    static func openStored(in core: CrestCore, favicons: any BrowserFaviconStoring) throws(Rejection)
        -> BrowserCoreSessionAuthority
    {
        let changes = try core.send(OpenWorkspace(kind: .persistent, seed: nil))
        let opened = Self.opened(by: changes)
        var images: [UUID: Data] = [:]
        for space in opened.session.spaces {
            for tab in space.tabs { images[tab.id] = favicons.favicon(tabID: tab.id) }
        }
        for case .tabCopied(let copied) in changes where copied.workspaceID == opened.workspaceID {
            images[copied.copyTabID] = favicons.favicon(tabID: copied.sourceTabID)
        }
        core.state.adoptImages(images, in: opened.workspaceID)
        return BrowserCoreSessionAuthority(opened: opened, core: core)
    }

    /// Opens a workspace that borrows the Space `assignment` names, with its
    /// profile, settings and access grants, and tabs of its own. It follows
    /// this workspace's edits of the Space's settings and closes once this
    /// workspace no longer lends it. Throws the rule that refuses it.
    func borrow(_ assignment: BrowserSpaceRuntimeAssignment) throws(Rejection) -> BrowserCoreSessionAuthority {
        guard let device else { preconditionFailure("A workspace lends its Space only while its core exists.") }
        let changes = try device.send(
            BorrowSpace(workspaceID: workspaceID, spaceID: assignment.spaceID, profileID: assignment.profileID)
        )
        return BrowserCoreSessionAuthority(opened: Self.opened(by: changes), core: device)
    }

    /// The workspace an intent that opens one announced.
    private static func opened(by changes: [Change]) -> WorkspaceOpened {
        for case .workspaceOpened(let opened) in changes.reversed() { return opened }
        preconditionFailure("The core opened a workspace without announcing it. Rebuild the core.")
    }

    // MARK: - Actions - Closing

    /// Closes the workspace, and first every workspace that borrows from it:
    /// its pages and windows go and its session takes no edits. The device
    /// keeps its windows' saved records. Closing it again does nothing.
    func close() {
        guard isOpen else { return }
        _ = try? device?.send(CloseWorkspace(workspaceID: workspaceID))
    }
}
