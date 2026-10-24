import SwiftUI

/// The card somebody is carrying, drawn at the pointer over everything.
///
/// A full-bleed layer in the source browser window's coordinates. The host moves
/// this canvas within its expanded preview window, so the card can follow the
/// pointer outside without changing the coordinates the carry already reports.
///
/// It is the card at its own size, risen by the house lift scale — not a token
/// standing in for one. A split card is half a window or more, so shrinking it
/// to a badge would have somebody rearranging something other than what they
/// picked up; at full size the neighbours are still visible around it, settling
/// into the order the release will keep.
///
/// The rise is scaled about the grabbed point rather than the card's centre,
/// which is what keeps the exact pixel somebody grabbed under the cursor. Only
/// the shape and the picture animate: animating the position as well would make
/// the card lag the pointer, which is the one thing a carry must never do.
struct BrowserSplitCardLiftFloatingPreview: View {
    let content: BrowserSplitCardLiftPreviewContent

    /// Read from outside the placement layer and handed back to the art, so a
    /// mirrored interface still places the card by real screen coordinates while
    /// its title and favicon read in the ambient direction.
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            art
                .environment(\.layoutDirection, layoutDirection)
                .scaleEffect(scale, anchor: grabAnchor)
                .opacity(content.isSettling ? 0 : 1)
                .offset(x: content.origin.x, y: content.origin.y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
        // The settle: the card is already back in the row underneath, so the
        // preview only has to descend onto it and go.
        .animation(settleMotion, value: content.isSettling)
        // The window behind this is transparent and click-through; this makes
        // certain nothing in the preview claims a hit test of its own.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The page, once WebKit has handed it over, and the tab standing in for it
    /// until then.
    ///
    /// Both are drawn, and the picture is faded in over the other: the pickup
    /// cannot wait for a snapshot, and a card that flashed from empty to page
    /// would advertise the wait it was meant to hide.
    private var art: some View {
        let shape = RoundedRectangle(
            cornerRadius: content.cornerRadius,
            style: .continuous
        )
        return ZStack {
            Rectangle().fill(.background)
            placeholder.opacity(content.snapshot == nil ? 1 : 0)
            if let snapshot = content.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .frame(width: content.size.width, height: content.size.height)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5)
        }
        .shadow(
            color: .black.opacity(0.28),
            radius: 18,
            y: 10
        )
        .animation(crossfadeMotion, value: content.snapshot != nil)
    }

    private var placeholder: some View {
        VStack(spacing: CrestSpacing.small) {
            TabFaviconView(subject: content.favicon, profileID: content.profileID, size: 32)
            Text(content.title)
                .font(CrestTypography.controlTitle)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, CrestSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grabAnchor: UnitPoint {
        UnitPoint(x: content.grabFraction.x, y: content.grabFraction.y)
    }

    private var scale: CGFloat {
        guard !content.isSettling else { return 1 }
        return BrowserSidebarReorderVisuals.liftScale.unlessReducingMotion(content.reduceMotion)
    }

    private var settleMotion: Animation? {
        CrestMotion.collection.unlessReducingMotion(content.reduceMotion)
    }

    private var crossfadeMotion: Animation? {
        CrestMotion.dragPreview.unlessReducingMotion(content.reduceMotion)
    }
}
