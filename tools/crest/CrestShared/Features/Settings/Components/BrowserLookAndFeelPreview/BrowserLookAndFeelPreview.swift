import Foundation
import SwiftUI

// MARK: - Types

/// How much of a window a Look and Feel preview shows.
///
/// The pinned preview shows the whole window; a group's own card shows only the
/// part that group changes, so the reader never has to hunt for what moved.
enum BrowserLookAndFeelPreviewFocus: Equatable {
    case window
    case page
    case tabs
    case addressField
    case folders
}

/// The live answer to "what does this do", built from the real sidebar.
///
/// Every control in the Look and Feel pane changes something here. The window
/// crop reads the border, the sidebar edge, the page corner, and the Space's
/// own atmosphere, while the sidebar inside it is the shipping one, so tab
/// scale, pin layout, corner radius, tab and folder appearance arrive without
/// this view knowing any of them by name.
///
/// Pinned beside the form, the crop fills whatever height it is given. At the
/// top of a card it takes a fixed height instead, so a compact pane still
/// scrolls like a form.
struct BrowserLookAndFeelPreview: View {
    var space: BrowserSpaceAppearance?
    var focus: BrowserLookAndFeelPreviewFocus = .window
    var fillsHeight = false

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("look-and-feel-preview")
    }

    @ViewBuilder
    private var content: some View {
        switch focus {
        case .window:
            if fillsHeight {
                BrowserLookAndFeelSidebarCrop(space: space)
                    .frame(maxHeight: .infinity)
            } else {
                BrowserLookAndFeelSidebarCrop(space: space)
                    .frame(height: BrowserLookAndFeelPreviewMetrics.inlineCropHeight)
            }
        case .page:
            BrowserLookAndFeelPagePreview()
        case .tabs:
            BrowserSidebarCustomizationPreview(space: space)
        case .folders:
            BrowserSidebarCustomizationPreview(space: space, showsPins: false)
        case .addressField:
            BrowserLookAndFeelAddressPreview(space: space)
        }
    }
}
