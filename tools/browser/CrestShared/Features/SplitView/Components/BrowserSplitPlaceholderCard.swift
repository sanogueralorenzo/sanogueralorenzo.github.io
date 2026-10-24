import SwiftUI

/// What the drop column of a split shows while it is still empty.
///
/// Only the interior. The column itself is a real slot in
/// `BrowserSplitColumnsView` — same `BrowserRootContentSurface`, same rounding,
/// same seam, same boundary stroke, same share of the row — so the card that
/// lands here on release replaces this content in a frame that is already
/// exactly its own. Drawing a border of its own would be the one thing that
/// gave the swap away.
struct BrowserSplitPlaceholderCard: View {
    private static let symbolSize: CGFloat = 22

    var body: some View {
        VStack(spacing: CrestSpacing.small) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: Self.symbolSize, weight: .regular))
            Text("Add to Split View")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(CrestSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
