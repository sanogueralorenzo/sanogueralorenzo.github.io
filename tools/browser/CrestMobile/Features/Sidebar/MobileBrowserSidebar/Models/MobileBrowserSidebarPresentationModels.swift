import SwiftUI

/// Presentation vocabulary owned by the adaptive mobile sidebar shell.

struct MobileBrowserSidebarSpaceSheet: Equatable, Identifiable {
    let surface: BrowserUtilitySurface
    let assignment: BrowserSpaceRuntimeAssignment

    var id: String {
        "\(surface.name)-\(assignment.spaceID)-\(assignment.profileID.uuidString)"
    }
}
