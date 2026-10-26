import Foundation

extension PagePresentation {
    // MARK: - Variables

    /// Whether a split card in this presentation has a WebKit rendering worth
    /// carrying.
    ///
    /// Only a live page does. Every other presentation is drawn by SwiftUI over
    /// a web view that is showing nothing — a start-page card never loads or
    /// mounts the page it was given, an unloaded card has not started one, and a
    /// failure card is covering whatever the page last had — so the picture
    /// WebKit would hand back is not the card anybody is looking at.
    ///
    /// The distinction matters because an empty picture is worse than none: the
    /// preview stands its title-and-favicon placeholder down the moment a
    /// snapshot arrives, so a blank one leaves the carry showing neither the page
    /// nor the tab. A card with nothing to picture must not ask.
    var picturesLivePage: Bool {
        self == .livePage
    }
}
