import SwiftUI

/// Resolves lifted items for the inert preview window above browser content.
/// A carried split card takes precedence over a sidebar lift.
struct BrowserRootDragPreviewLayer: View {
    let model: BrowserRootModel
    let reduceMotion: Bool

    @Environment(\.browserWindowCornerRadius) private var windowCornerRadius

    private var appearance: BrowserChromeAppearance { .device(windowCornerRadius: windowCornerRadius) }

    var body: some View {
        BrowserDragPreviewWindowBridge(
            content: content,
            onSidebarLandingComplete: model.sidebarInteraction.sidebarReorderState.finishLanding,
            onSidebarLandingArrived: model.sidebarInteraction.sidebarReorderState.revealLanding
        )
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var content: BrowserDragPreviewWindowContent? {
        if let card = splitCardLiftContent {
            return .splitCardLift(card)
        }
        if let sidebar = sidebarLiftContent {
            return .sidebarLift(sidebar)
        }
        return nil
    }

    /// A carried card always belongs to the Space on show: only presented cards
    /// can be picked up, and a Space change ends the carry with the row it came
    /// from.
    private var splitCardLiftContent: BrowserSplitCardLiftPreviewContent? {
        guard let lift = model.splitCardLift.lift,
            let space = model.browser.shownSpace,
            let tab = space.tabs.model(lift.tabID)
        else { return nil }
        return BrowserSplitCardLiftPreviewContent(
            favicon: BrowserTabFaviconSubject(tab: tab, image: model.browser.core.state.favicons.icon(of: tab.id)),
            title: tab.shownTitle,
            profileID: space.profileID,
            snapshot: lift.snapshot,
            origin: lift.previewOrigin,
            size: lift.cardSize,
            // A borderless card has square corners only because it meets the
            // window's edges; lifted away from them, it rounds like a page.
            cornerRadius: appearance.borderless
                ? BrowserChromeLayout.pageCornerRadius
                : appearance.pageCornerRadius,
            grabFraction: lift.grabFraction,
            isSettling: lift.isSettling,
            reduceMotion: reduceMotion
        )
    }

    /// A lifted row always belongs to the Space on show: the sidebar only offers
    /// the selected Space's rows as drag sources, so a lift that reaches this
    /// point is one of these by construction.
    private var sidebarLiftContent: BrowserSidebarLiftPreviewContent? {
        guard let lift = model.sidebarInteraction.sidebarReorderState.liftPreview,
            let space = model.browser.spaceModel(model.browser.selectedSpaceID),
            let subject = subject(for: lift.item, in: space)
        else { return nil }
        return BrowserSidebarLiftPreviewContent(
            subject: subject,
            favicons: model.browser.core.state.favicons,
            lift: lift,
            reduceMotion: reduceMotion,
            selectedTabID: model.browser.selectedTabID(in: space.id),
            loadedTabIDs: model.pages.retainedTabIDs
        )
    }

    private func subject(
        for item: BrowserSidebarReorderItem,
        in space: SpaceModel
    ) -> BrowserSidebarLiftPreviewSubject? {
        if item.selection != nil, let lift = model.sidebarInteraction.sidebarReorderState.liftPreview {
            let rows = BrowserSidebarSelectionPreviewRow.resolve(lift.previewRows, in: space) { folderID in
                model.sidebarInteraction.sidebarReorderState.folderPreviewRows(
                    for: .folder(
                        BrowserFolderDragItem(
                            folderID: folderID, spaceID: space.id, profileID: space.profileID)))
            }
            return rows.isEmpty ? nil : .selection(rows)
        }
        return item.liftPreviewSubject(
            in: space, previewRows: model.sidebarInteraction.sidebarReorderState.liftPreview?.previewRows ?? [])
    }
}
