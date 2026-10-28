import SwiftUI

/// The same title and favicon in the list and in the travelling component.
/// Keeping the native Label layout also preserves its baseline and icon gap.
struct BrowserSidebarTabLabelContent: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let metrics: BrowserSidebarTabRowMetrics
    var leadingInset: CGFloat = 0
    var titleOpacity = 1.0
    var iconOffset: CGFloat = 0
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(BrowserGitHubIntegration.self) private var github: BrowserGitHubIntegration?
    /// The core whose page states name a tab whose page failed to load. None
    /// where no window supplies one, such as a drag preview.
    @Environment(CrestCore.self) private var core: CrestCore?
    let textScale: Double

    private var isLiveFolderItem: Bool { tab.folderID != nil && tab.folderID == github?.folderID }

    private var author: String? {
        guard let github, tab.folderID == github.folderID,
            let author = github.items.first(where: { $0.url.absoluteString == (tab.savedURL ?? tab.url) })?.author,
            !author.isEmpty
        else { return nil }
        return author
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                Text(tab.shownTitle(in: isLoaded ? core?.state : nil))
                    .modifier(BrowserSidebarDensityFont(scale: textScale, supportsTouch: capabilities.supportsTouch))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let author {
                    Text(verbatim: author).font(CrestTypography.compactMetadata).foregroundStyle(.secondary).lineLimit(
                        1)
                }
            }
            .browserTabResidency(isLoaded: isLoaded || isLiveFolderItem)
            .opacity(titleOpacity)
        } icon: {
            BrowserSidebarTabFaviconContent(
                tab: tab, favicons: favicons, profileID: profileID, metrics: metrics,
                isProminent: isSelected, isLoaded: isLoaded || isLiveFolderItem,
                iconScale: textScale
            )
            .offset(x: iconOffset)
        }
        .padding(.leading, leadingInset)
        .frame(maxWidth: .infinity, maxHeight: metrics.fillsRowHeight ? .infinity : nil, alignment: .leading)
        .contentShape(.rect)
    }
}
