import SwiftUI

extension BrowserTransientCardArrangement {
    /// The arrangement a window of these size classes has room for.
    ///
    /// A window that is compact either way has no room to float a card, so its
    /// overlay fills the safe area and is pushed away with a thumb; one that is
    /// regular both ways, an iPad or an open iPhone Duo, has room to leave the
    /// scrim showing and let a tap on it close the card.
    static func fitting(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> BrowserTransientCardArrangement {
        horizontalSizeClass == .regular && verticalSizeClass == .regular ? .canvas : .sheet
    }
}
