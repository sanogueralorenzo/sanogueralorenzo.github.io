import SwiftUI

/// The count of new downloads on a Space control: Crest's own badge beside the
/// glyph in the capsule, or the system's where the control is a toolbar item,
/// since the bar draws its items' content in its own vibrant style and clips
/// anything outside them.
struct MobileSpaceUtilityBadge: ViewModifier {
    let count: Int
    let tint: Color
    let progress: Double?

    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement

    func body(content: Content) -> some View {
        if controlPlacement.movesControlsToToolbar {
            content.badge(count)
        } else {
            content
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        BrowserUtilityNotificationBadge(
                            count: count,
                            tint: tint,
                            progress: progress
                        )
                        .offset(
                            x: BrowserUtilitySwitcherLayout.notificationBadgeOffset,
                            y: -BrowserUtilitySwitcherLayout.notificationBadgeOffset
                        )
                    }
                }
                .zIndex(count == 0 ? 0 : 1)
        }
    }
}
