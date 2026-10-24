import Foundation
import Observation

/// Updates the existing preview tree instead of replacing its hosting root on
/// every pointer sample, which also reinstalled the entire SwiftUI environment.
@Observable
@MainActor
final class BrowserDragPreviewWindowPresentation {
    var content: BrowserDragPreviewWindowContent
    var canvasFrame: CGRect
    @ObservationIgnored var onSidebarLandingComplete: (UUID) -> Void = { _ in }
    @ObservationIgnored var onSidebarLandingArrived: (UUID) -> Void = { _ in }

    init(content: BrowserDragPreviewWindowContent, canvasFrame: CGRect) {
        self.content = content
        self.canvasFrame = canvasFrame
    }
}
