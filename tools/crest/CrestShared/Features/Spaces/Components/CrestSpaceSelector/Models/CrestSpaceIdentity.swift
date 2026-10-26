import SwiftUI

/// The identity a Space picker draws, including its name and color.
/// `displayName` can show a draft name before it is committed.
struct CrestSpaceIdentity: Identifiable, Equatable {
    let space: BrowserSpaceIdentity
    var displayName: String?
    var tintOverride: Color?

    var id: UUID { space.id }
    var name: String { displayName ?? space.name }
    var tint: Color { tintOverride ?? CrestBrandTheme.accent }

    @MainActor
    init(space: some BrowserSpaceIdentifying, displayName: String? = nil, tint: Color? = nil) {
        self.space = space.identity
        self.displayName = displayName
        tintOverride = tint
    }

    /// Spaces of the read model, or values no session holds yet, such as
    /// drafts and previews.
    @MainActor
    static func list(_ spaces: [some BrowserSpaceIdentifying]) -> [CrestSpaceIdentity] {
        spaces.map { CrestSpaceIdentity(space: $0) }
    }
}
