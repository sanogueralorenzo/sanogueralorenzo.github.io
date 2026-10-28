import SwiftUI

/// The whole of what the drag preview window shows: one lifted row, drawn at the
/// pointer, over nothing.
///
/// A full-bleed layer in the source browser window's coordinates. The host moves
/// this canvas within its expanded preview window, so the art can follow the
/// pointer outside without changing the coordinates the drag already reports.
///
/// The art is the sidebar's own drag art — a tab morphing between its row, the
/// pinned tile, and the page-shaped card; a folder row; a stack of split-group
/// member lines — so moving where a lift is drawn changed nothing about what it
/// looks like.
///
/// Everything it needs arrives as a value. It reads no drag state, resolves no
/// tab, and owns no window; the host observes the reorder state and hands the
/// result down, which is what keeps a preview drawn in a second window a
/// presentation of the one drag rather than a copy of it.
struct BrowserSidebarLiftFloatingPreview: View {
    let subject: BrowserSidebarLiftPreviewSubject
    let favicons: FaviconAssets
    let lift: BrowserSidebarFloatingLift
    /// Passed in rather than read from the environment: this view is hosted in a
    /// window of its own, which inherits nothing from the browser's.
    var reduceMotion = false
    var onLandingComplete: (UUID) -> Void = { _ in }
    var onLandingArrived: (UUID) -> Void = { _ in }
    var selectedTabID: UUID?
    var loadedTabIDs: Set<UUID> = []
    @State private var landedFrame: CGRect?
    @State private var previewOpacity = 1.0
    @State private var stackHasGathered = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            art
                .scaleEffect(
                    x: scale.width, y: scale.height,
                    anchor: UnitPoint(x: lift.anchorFraction.x, y: lift.anchorFraction.y)
                )
                .offset(x: -displayAnchor.width, y: -displayAnchor.height)
                .animation(
                    CrestMotion.dragPreview.unlessReducingMotion(reduceMotion),
                    value: lift.shape
                )
                .offset(x: displayPointer.x, y: displayPointer.y)
                .opacity(previewOpacity)
            if let message = lift.constraintMessage {
                Label(message, systemImage: "nosign")
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: 280, alignment: .leading)
                    .background {
                        CrestSurfaceLayer(shape: .rect(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: 0)))
                    }
                    .offset(x: displayPointer.x + 12, y: displayPointer.y + lift.sourceSize.height + 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Only the shape settles. Animating the position as well would make the
        // preview lag the pointer, which is the one thing a lift must never do.
        // The window behind this is transparent and click-through; this makes
        // certain nothing in the preview claims a hit test of its own.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(
                CrestMotion.dragSource.unlessReducingMotion(reduceMotion)
            ) {
                stackHasGathered = true
            }
        }
        .onChange(of: lift.landing, initial: true) { _, landing in
            guard let landing else {
                landedFrame = nil
                previewOpacity = 1
                return
            }
            if landing.isRevealing {
                withAnimation(
                    Animation.easeOut(duration: 0.10).unlessReducingMotion(reduceMotion),
                    completionCriteria: .removed
                ) {
                    previewOpacity = 0
                } completion: {
                    onLandingComplete(landing.id)
                }
                return
            }
            withAnimation(
                CrestMotion.dragSource.unlessReducingMotion(reduceMotion),
                completionCriteria: .removed
            ) {
                landedFrame = landing.frame
            } completion: {
                onLandingArrived(landing.id)
            }
        }
    }

    private var artSize: CGSize {
        subject.artSize(of: lift, rowWidth: rowWidth, pinnedSize: pinnedSize)
    }

    /// Resize layout rather than scaling glyphs to meet the destination. A
    /// source tile and a full sidebar row do not have the same measured width.
    private var rowWidth: CGFloat { landedFrame?.width ?? lift.rowWidth }
    private var pinnedSize: CGSize { landedFrame?.size ?? lift.pinnedTileSize }
    private var displayAnchor: CGSize {
        subject.displayAnchor(of: lift, artSize: artSize)
    }

    private var scale: CGSize {
        subject.scale(artSize: artSize, landedFrame: landedFrame, reduceMotion: reduceMotion)
    }

    private var displayPointer: CGPoint {
        guard let landedFrame else { return lift.presentationPointer }
        return subject.landedPointer(of: lift, in: landedFrame, pinnedSize: pinnedSize)
    }

    @ViewBuilder
    private var art: some View {
        switch subject {
        case .tab(let tab):
            BrowserTabDragPreview(
                tab: tab,
                favicons: favicons,
                profileID: lift.profileID,
                targetShape: lift.shape,
                progress: lift.progress,
                rowWidth: rowWidth,
                pinnedSize: pinnedSize,
                isSelected: tab.id == selectedTabID,
                isLoaded: loadedTabIDs.contains(tab.id)
            )
        case .folder(let folder, let rows):
            BrowserFolderDragPreview(
                folder: folder, favicons: favicons, rowWidth: rowWidth,
                sourceHeight: lift.sourceSize.height, rows: rows, profileID: lift.profileID,
                loadedTabIDs: loadedTabIDs)
        case .selection(let rows):
            selectionStack(rows)
        case .splitGroup(let members):
            BrowserSplitGroupDragPreview(
                members: members,
                favicons: favicons,
                profileID: lift.profileID,
                rowWidth: rowWidth
            )
        }
    }

    private func compactOffset(for id: BrowserSidebarReorderItemID, in rows: [BrowserSidebarSelectionPreviewRow])
        -> CGFloat
    {
        BrowserSidebarSelectionPreviewRow.stackOffset(of: id, in: rows, shape: lift.shape, pinnedSize: pinnedSize)
    }

    private func selectionStack(_ rows: [BrowserSidebarSelectionPreviewRow]) -> some View {
        let lead = rows.first { $0.id == lift.item.id } ?? rows[0]
        let leadOffset = compactOffset(for: lead.id, in: rows)
        return ZStack(alignment: .topLeading) {
            ForEach(rows) { row in
                selectionRow(row)
                    .offset(
                        x: stackHasGathered || reduceMotion ? 0 : row.frame.minX - lead.frame.minX,
                        y: stackHasGathered || reduceMotion
                            ? compactOffset(for: row.id, in: rows) - leadOffset
                            : row.frame.minY - lead.frame.minY)
            }
        }
        .frame(width: rowWidth, height: lead.frame.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func selectionRow(_ row: BrowserSidebarSelectionPreviewRow) -> some View {
        if let folder = row.folder {
            BrowserFolderDragPreview(
                folder: folder, favicons: favicons, rowWidth: rowWidth, sourceHeight: row.frame.height,
                rows: row.folderRows, profileID: lift.profileID, loadedTabIDs: loadedTabIDs)
        } else if row.isSplit {
            BrowserSplitGroupDragPreview(
                members: row.tabs, favicons: favicons, profileID: lift.profileID, rowWidth: rowWidth,
                sourceHeight: row.frame.height, loadedTabIDs: loadedTabIDs)
        } else if let tab = row.tabs.first {
            BrowserTabDragPreview(
                tab: tab, favicons: favicons, profileID: lift.profileID,
                targetShape: lift.shape == .pinnedTile ? .pinnedTile : .row,
                progress: lift.shape == .pinnedTile ? 1 : 0,
                rowWidth: rowWidth, pinnedSize: pinnedSize,
                isSelected: tab.id == selectedTabID, isLoaded: loadedTabIDs.contains(tab.id))
        }
    }
}
