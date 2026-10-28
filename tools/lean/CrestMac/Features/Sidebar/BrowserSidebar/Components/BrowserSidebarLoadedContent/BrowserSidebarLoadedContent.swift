import AppKit
import SwiftUI

/// The windowed shell's sidebar layout: a clipped Space pager tucked under the
/// navigation and Space controls.
///
/// Everything about *what* the sidebar does comes down from `BrowserSidebar`
/// through the context. This view arranges the chrome and the page body only a
/// windowed card pool can answer for.
struct BrowserSidebarLoadedContent: View {
    let context: BrowserSidebarContext
    let pages: BrowserPagePool
    let activateAddress: () -> Void
    let openNewTab: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.spacePagerPresentation) private var inheritedPagerPresentation
    @State private var standalonePagerPresentation = SpacePagerPresentation()

    private var spacePagerPresentation: SpacePagerPresentation {
        inheritedPagerPresentation ?? standalonePagerPresentation
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                SidebarChrome(
                    context: context,
                    pages: pages,
                    activateAddress: activateAddress,
                    openNewTab: openNewTab
                )

                if !context.browser.isPrivateBrowsing {
                    BrowserNowPlayingSidebar(
                        activateMediaSession: activateMediaSession,
                        ownerFaviconData: ownerFaviconData
                    )
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                // The pager already reaches the glow's outset up under the chrome.
                spacePagerPresentation.gestureTopInset = $0
            }
            .zIndex(1)

            BrowserSidebarSpacePager(context: context) { space, isSelected in
                BrowserSidebarSpacePage(
                    space: space,
                    isSelected: isSelected,
                    context: context,
                    pages: pages,
                    openNewTab: openNewTab,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    tabPromotionNamespace: tabPromotionNamespace
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .environment(\.spacePagerPresentation, spacePagerPresentation)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(context.browser.shownSpace?.settings.name ?? "Browser") Space"
        )
    }

    private func activateMediaSession(
        _ assignment: BrowserTabRuntimeAssignment
    ) {
        Task { @MainActor in
            guard
                pages.containsResidentPage(matching: assignment),
                let space = context.browser.spaceModel(matching: assignment.spaceAssignment),
                space.tabs.model(assignment.tabID) != nil
            else { return }
            context.selectSpace(assignment.spaceID)
            context.browser.selectTab(assignment.tabID)
            pages.select()
        }
    }

    private func ownerFaviconData(
        _ assignment: BrowserTabRuntimeAssignment
    ) -> Data? {
        guard context.browser.spaceModel(matching: assignment.spaceAssignment)?.tabs.model(assignment.tabID) != nil
        else { return nil }
        return context.browser.core.state.favicons.image(of: assignment.tabID)
    }

}
