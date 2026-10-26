import SwiftUI

/// What a lifted split group looks like under the finger: the grouped container
/// with its count affordance and one line per member, so the run reads as the
/// single block it moves as.
///
/// Scoped rather than left to the system's own snapshot, for the reason the tab
/// and folder previews are: a sidebar row is inset inside its own bounds, and
/// the default lift plate is the full row rectangle — wider than the surface it
/// is meant to be lifting, with the plate's own background showing around it.
struct BrowserSplitGroupDragPreview: View {
    let members: [TabStateModel]
    let favicons: FaviconAssets
    let profileID: UUID
    var rowWidth = BrowserTabDragPreviewLayout.rowSize.width
    var sourceHeight: CGFloat?
    var loadedTabIDs: Set<UUID>?

    private static let containerPadding = BrowserSidebarMetrics.containerPadding
    private static let lineSpacing: CGFloat = CrestSpacing.extraExtraSmall
    private static let headerHeight: CGFloat = 20
    private static let headerGlyphSize: CGFloat = 11
    /// Compact next to the row's own 44pt touch targets: the preview stands for
    /// the run, and a full-height stack of four would fill the sidebar.
    private static let memberLineHeight: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous)

        VStack(spacing: Self.lineSpacing) {
            header
            ForEach(members, id: \.id) { member in
                line(for: member)
            }
        }
        .padding(Self.containerPadding)
        .frame(width: BrowserTabDragPreviewLayout.resolvedRowWidth(rowWidth))
        .background { CrestSurfaceLayer(shape: shape) }
        .overlay {
            shape.strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Split View with \(members.count) tabs")
    }

    private var header: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: Self.headerGlyphSize, weight: .semibold))
            Text(members.count, format: .number)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .frame(height: Self.headerHeight)
    }

    private func line(for member: TabStateModel) -> some View {
        HStack(spacing: CrestSpacing.small) {
            TabStateFaviconView(tab: member, favicons: favicons, profileID: profileID, size: 18)
                .frame(width: 20)
            Text(member.shownTitle)
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CrestSpacing.small)
        .frame(
            height: sourceHeight.map {
                max(
                    Self.memberLineHeight,
                    ($0 - Self.containerPadding * 2 - Self.headerHeight - Self.lineSpacing * CGFloat(members.count))
                        / CGFloat(max(members.count, 1)))
            } ?? Self.memberLineHeight
        )
        .browserTabResidency(isLoaded: loadedTabIDs?.contains(member.id) ?? true)
        .allowsHitTesting(false)
    }
}
