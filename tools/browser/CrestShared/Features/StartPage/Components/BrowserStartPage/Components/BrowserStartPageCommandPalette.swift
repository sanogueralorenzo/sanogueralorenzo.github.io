import SwiftUI

/// The command palette as the start page embeds it.
///
/// The palette is rebuilt whenever the tab it speaks for changes, and — where a
/// shell raises focus requests — whenever its address field asks for the
/// keyboard again, so a stale query never survives into another tab's page.
///
/// It offers the window's commands only once something is typed: a page with
/// an empty field suggests none.
struct BrowserStartPageCommandPalette: View {
    let page: BrowserStartPage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        promotedPalette
            .accessibilityIdentifier("start-page-command-palette")
            .accessibilityHidden(page.isCommandPaletteObscured)
    }

    @ViewBuilder
    private var promotedPalette: some View {
        if let promotion = page.promotion, !reduceMotion {
            palette.matchedGeometryEffect(
                id: promotion.id,
                in: promotion.namespace,
                properties: .frame,
                anchor: .center,
                isSource: true
            )
        } else {
            palette
        }
    }

    private var palette: some View {
        BrowserCommandPalette(
            browser: page.browser,
            space: page.space,
            selectedTabID: page.selectedTabID,
            commands: page.commands,
            offersRestingCommands: false,
            isSourceAvailable: page.isSourceAvailable,
            selectTab: page.selectTab,
            openURL: { source, url, _ in page.openURL(source, url) },
            dismiss: {},
            presentation: .embedded,
            emptySelectionActions: page.emptySelectionActions
        )
        .id(
            BrowserCommandPalettePresentationIdentity(
                focusRequest: page.focusRequest,
                space: page.space,
                source: sourceAssignment
            )
        )
    }

    private var sourceAssignment: BrowserTabRuntimeAssignment? {
        guard let space = page.space, let selectedTabID = page.selectedTabID
        else { return nil }
        return BrowserTabRuntimeAssignment(tabID: selectedTabID, spaceID: space.id, profileID: space.profileID)
    }
}
