import SwiftUI

/// The one root view the drag preview window hosts, whichever kind of thing is
/// travelling on the pointer.
///
/// It exists so the host owns a single `NSHostingView` for the life of a window
/// rather than a generic one per kind of lift: the panel, the hosting view, and
/// the appearance are the same machinery for a sidebar row and for a Split View
/// card, and only the art differs. Each case is that feature's own preview,
/// unchanged by being drawn somewhere else.
struct BrowserDragPreviewWindowFloatingContent: View {
    let presentation: BrowserDragPreviewWindowPresentation

    var body: some View {
        preview
            .frame(width: presentation.canvasFrame.width, height: presentation.canvasFrame.height)
            .offset(x: presentation.canvasFrame.minX, y: presentation.canvasFrame.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var preview: some View {
        switch presentation.content {
        case .sidebarLift(let sidebar):
            BrowserSidebarLiftFloatingPreview(
                subject: sidebar.subject,
                favicons: sidebar.favicons,
                lift: sidebar.lift,
                reduceMotion: sidebar.reduceMotion,
                onLandingComplete: presentation.onSidebarLandingComplete,
                onLandingArrived: presentation.onSidebarLandingArrived,
                selectedTabID: sidebar.selectedTabID,
                loadedTabIDs: sidebar.loadedTabIDs
            )
        case .splitCardLift(let card):
            BrowserSplitCardLiftFloatingPreview(content: card)
        }
    }
}
