import SwiftUI

/// The values a retained sidebar page draws from, independent of the Space the
/// window shows: whose page it is, whether it is unlocked, and the look it
/// wears. It names no tab or folder, so it changes only when the page's lock
/// or look does. This is presentation data, never authority for an action.
struct SidebarSpacePresentation: Equatable {
    let assignment: BrowserSpaceRuntimeAssignment
    let isUnlocked: Bool
    let branding: SpaceBranding

    @MainActor
    init(space: SpaceModel, isUnlocked: Bool) {
        assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        self.isUnlocked = isUnlocked
        branding = space.settings.look
    }

    func isAvailable(matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        self.assignment == assignment && isUnlocked
    }
}

/// A page's input role is separate from the values its rows draw. Shells that
/// omit the role already include live selection in their availability checks.
enum SidebarSpaceRole {
    static func permitsInteraction(isSelected: Bool?, isAvailable: Bool) -> Bool {
        isAvailable && isSelected != false
    }
}

extension EnvironmentValues {
    /// Shells without retained page roots keep their existing live reads.
    @Entry var sidebarSpacePresentation: SidebarSpacePresentation? = nil
    /// Read by interaction and editor-cleanup leaves, not row configurations.
    @Entry var sidebarSpaceIsSelected: Bool? = nil
    /// Set by every shell surface that draws a Space's rows. Leaves that would
    /// otherwise reach the network for a row's content (favicons) must not do so
    /// while the Space is locked: the request itself discloses the hostnames.
    @Entry var browserSpaceContentIsLocked: Bool = false
}
