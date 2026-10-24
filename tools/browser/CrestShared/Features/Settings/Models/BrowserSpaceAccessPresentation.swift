import SwiftUI

enum BrowserSpaceAccessPresentation: Equatable {
    case standalone
    case contentOverlay

    var showsSpaceMenu: Bool {
        self == .standalone
    }
}
