import SwiftUI

struct BrowserFolderDragPreview: View {
    let folder: FolderStateModel
    var favicons: FaviconAssets? = nil
    var rowWidth = BrowserTabDragPreviewLayout.rowSize.width
    var sourceHeight: CGFloat = BrowserFolderDragPreviewLayout.height
    var rows: [BrowserFolderDragPreviewRow] = []
    var profileID: UUID?
    var loadedTabIDs: Set<UUID>?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous)
        let width = BrowserFolderDragPreviewLayout.width(for: rowWidth)

        ZStack(alignment: .topLeading) {
            folderHeader(folder)
                .frame(height: BrowserFolderDragPreviewLayout.height)
            ForEach(rows) { row in
                rowContent(row)
                    .frame(width: width, height: row.previewHeight, alignment: .topLeading)
                    .offset(y: row.frame.minY)
            }
        }
        .frame(width: width, height: max(BrowserFolderDragPreviewLayout.height, sourceHeight), alignment: .topLeading)
        .background { CrestSurfaceLayer(shape: shape) }
        .overlay {
            shape.fill(folder.displayColor.color.opacity(0.12))
            shape.strokeBorder(folder.displayColor.color.opacity(0.35), lineWidth: 0.5)
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(folder.title) folder")
    }

    private func folderHeader(_ folder: FolderStateModel, depth: Int = 0) -> some View {
        HStack(spacing: CrestSpacing.small) {
            let color = folder.displayColor
            BrowserFolderArtwork(symbol: folder.displaySymbol, color: color, isExpanded: !folder.isCollapsed)
                .foregroundStyle(color.color.opacity(0.86))
                .frame(width: 20)
            Text(folder.title).lineLimit(1)
            Spacer(minLength: CrestSpacing.small)
        }
        .padding(.leading, CrestSpacing.medium + CGFloat(depth) * BrowserFolderLayout.nestingIndent)
        .padding(.trailing, CrestSpacing.medium)
    }

    @ViewBuilder
    private func rowContent(_ row: BrowserFolderDragPreviewRow) -> some View {
        switch row.content {
        case .folder(let child, let depth):
            folderHeader(child, depth: depth)
        case .tab(let tab):
            tabLine(tab, leadingInset: max(BrowserFolderLayout.nestingIndent, row.frame.minX))
        case .splitGroup(let members):
            VStack(spacing: 0) {
                Label("\(members.count)", systemImage: "rectangle.split.2x1")
                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(members, id: \.id) { tab in tabLine(tab, leadingInset: 0).frame(maxHeight: .infinity) }
            }
            .padding(BrowserSidebarMetrics.containerPadding)
            .background {
                CrestSurfaceLayer(
                    shape: .rect(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: 1), style: .continuous))
            }
            .padding(.leading, max(BrowserFolderLayout.nestingIndent, row.frame.minX))
        }
    }

    private func tabLine(_ tab: TabStateModel, leadingInset: CGFloat) -> some View {
        HStack(spacing: CrestSpacing.small) {
            if let profileID, let favicons {
                TabStateFaviconView(tab: tab, favicons: favicons, profileID: profileID, size: 18).frame(width: 20)
            }
            Text(tab.shownTitle).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CrestSpacing.medium + leadingInset)
        .padding(.trailing, CrestSpacing.medium)
        .frame(maxHeight: .infinity)
        .browserTabResidency(isLoaded: loadedTabIDs?.contains(tab.id) ?? true)
    }
}
