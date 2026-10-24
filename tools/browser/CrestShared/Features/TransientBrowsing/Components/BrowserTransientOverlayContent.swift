import SwiftUI

/// Chooses what a transient overlay shows: the page, the lock that stands in
/// front of it, or the notice that its Space has gone.
///
/// A Peek or Quick Window borrows a Space, and a borrowed Space can be locked
/// or deleted while the overlay is open. Both shells answer that the same way,
/// so the choice is made once here and each shell supplies only its own
/// unlocked content.
struct BrowserTransientOverlayContent<UnlockedContent: View>: View {
    let requestID: UUID
    let space: SpaceModel?
    let spaces: [SpaceModel]
    let spaceAccess: BrowserSpaceAccessController
    let unavailableSpacePresentation: BrowserTransientUnavailableSpacePresentation
    let selectSpace: (BrowserSpaceRuntimeAssignment) -> Void
    let dismissUnavailable: () -> Void
    let unlockedContent: UnlockedContent

    init(
        requestID: UUID,
        space: SpaceModel?,
        spaces: [SpaceModel],
        spaceAccess: BrowserSpaceAccessController,
        unavailableSpacePresentation: BrowserTransientUnavailableSpacePresentation,
        selectSpace: @escaping (BrowserSpaceRuntimeAssignment) -> Void,
        dismissUnavailable: @escaping () -> Void,
        @ViewBuilder unlockedContent: () -> UnlockedContent
    ) {
        self.requestID = requestID
        self.space = space
        self.spaces = spaces
        self.spaceAccess = spaceAccess
        self.unavailableSpacePresentation = unavailableSpacePresentation
        self.selectSpace = selectSpace
        self.dismissUnavailable = dismissUnavailable
        self.unlockedContent = unlockedContent()
    }

    var body: some View {
        if let space {
            if spaceAccess.isLocked(space) {
                BrowserSpaceAccessView(
                    space: space,
                    spaces: spaces,
                    accessController: spaceAccess,
                    selectSpace: selectSpace
                )
            } else {
                unlockedContent
            }
        } else {
            BrowserTransientUnavailableSpaceView(
                requestID: requestID,
                presentation: unavailableSpacePresentation,
                dismiss: dismissUnavailable
            )
        }
    }
}
