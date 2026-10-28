import SwiftUI

struct SidebarSpacePresentation: Equatable {
    let assignment: BrowserSpaceRuntimeAssignment

    @MainActor
    init(space: SpaceModel) {
        assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
    }

    func isAvailable(matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        self.assignment == assignment
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
}
