import SwiftUI

extension BrowserInteractionCapabilities {
    // MARK: - Static Variables

    /// The floor a touch row grows to once the reader has chosen an
    /// accessibility text size, which no longer fits the resting row height.
    static let accessibilityTouchRowHeight: CGFloat = 56

    // MARK: - Variables

    /// Whether a row may keep its trailing control hidden until the pointer
    /// arrives over it.
    ///
    /// Hide-until-hover is only safe where hover exists *and* touch does not:
    /// a finger has no way to ask a row to reveal anything, so a control that
    /// waits for hover is simply unreachable there. An attached trackpad does
    /// not buy the trade back, because the same row still has to answer to a
    /// finger.
    var revealsRowControlsOnHoverOnly: Bool {
        supportsHover && !supportsTouch
    }

    /// The geometry and reveal behavior of a row's trailing close or unload
    /// control.
    ///
    /// Touch decides this rather than hover: the control has to be hittable by
    /// the least precise input the shell accepts, and a control sized for a
    /// finger is also the one that has to stay on screen.
    var trailingControlMetrics: BrowserTabTrailingControlMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The layout a tab row draws itself with.
    ///
    /// Touch decides this for the same reason it decides the trailing control:
    /// the insets, the favicon column, and the height behaviour all follow
    /// from the least precise input the shell accepts.
    var tabRowMetrics: BrowserSidebarTabRowMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The layout a stacked split-group row draws its container with.
    ///
    /// Touch decides this for the same reason it decides the tab row: the
    /// grouped surface has to hold rows a finger can tell apart, and the
    /// header above them has to be legible at the same distance.
    var splitGroupRowMetrics: BrowserSidebarSplitGroupRowMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The layout a saved folder's header draws itself with.
    ///
    /// Touch decides this for the same reason it decides the tab row: the
    /// symbol column, the trailing inset, and the height behaviour all follow
    /// from the least precise input the shell accepts, and the header has to
    /// sit in the same column as the rows it opens onto.
    var savedFolderHeaderMetrics: BrowserFolderHeaderMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The geometry the sidebar's new-tab row draws itself with.
    ///
    /// Touch decides this like it decides the rows below it: the row is a hit
    /// target, its height has to be able to grow with the label, and the hover
    /// surface a pointer shell rests under it is not a treatment a finger can
    /// ask for.
    var newTabRowMetrics: BrowserSidebarNewTabRowMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The geometry the tab list's own furniture draws itself with — the seam
    /// between the saved and current runs, and the band an empty run keeps for
    /// a drop.
    ///
    /// Touch decides this too. The seam's clear control and the drop band must
    /// accommodate the least precise input the shell accepts.
    var tabListMetrics: BrowserSidebarTabListMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The geometry the sidebar's address field draws itself with.
    ///
    /// Touch decides this like it decides the rows: the field is a hit target
    /// before it is a label, so its band, its gutter, and the controls inside
    /// it are all sized for the least precise input the shell accepts.
    var addressFieldMetrics: BrowserSidebarAddressFieldMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The geometry the sidebar's navigation strip draws itself with.
    ///
    /// Touch decides this too. The back, forward, and reload controls sit
    /// shoulder to shoulder, so the least precise input the shell accepts is
    /// what sets both their targets and the gaps between them.
    var navigationControlMetrics: BrowserSidebarNavigationControlMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The layout the Space header draws itself with.
    ///
    /// Touch decides this for the same reason it decides the tab row: the
    /// icon, the disclosure chevron, and the actions menu all have to answer
    /// to the least precise input the shell accepts, and a menu sized for a
    /// finger is also the one whose row can no longer be a fixed band.
    var spaceHeaderMetrics: BrowserSpaceHeaderMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// The geometry one Space's segment in the switcher draws itself with.
    ///
    /// Touch decides this like everything else the reader has to aim at: the
    /// crest is the target, so it is sized for the least precise input the
    /// shell accepts.
    var spacePickerMetrics: BrowserSpacePickerMetrics {
        supportsTouch ? .touch : .pointer
    }

    /// How the Space switcher lays its Spaces out.
    ///
    /// Touch decides the arrangement rather than the styling, because the two
    /// arrangements answer different questions. Segments a finger can hit stop
    /// fitting side by side after a handful of Spaces, so a touch shell needs
    /// a track that scrolls and centres the selection. A pointer shell keeps
    /// every Space on screen at once and spends the room it saves on the
    /// accessories that flank the strip.
    var spaceSwitcherArrangement: BrowserSpaceSwitcherArrangement {
        supportsTouch ? .scrollingSegments : .compactStrip
    }

    /// Whether a row anchors the surface that grows out of it with a
    /// matched-geometry destination.
    ///
    /// Two things have to be true, and neither implies the other. There must be
    /// a pairing to join at all — `pairsRowWithPromotedSurface` — and the shell
    /// must not already be joining it through the system's navigation zoom,
    /// which registers the row as that transition's source under the same
    /// identity. Two anchors on one identity are two answers to the same
    /// question.
    ///
    /// Reading this as "anything but the native zoom" is what broke the compact
    /// shell's reorder lift: its floating and regular placements have no pairing
    /// *and* no native zoom, so every row was handed a partnerless geometry
    /// anchor — a presentation transform sitting over the view
    /// `BrowserPlatformTabDragSourceModifier` hands to the system drag
    /// interaction. The tab viewer, which does use the native zoom, kept
    /// lifting; those two placements stopped.
    var usesMatchedGeometryPromotionDestination: Bool {
        pairsRowWithPromotedSurface
            && !usesNativeNavigationTransition
    }

    // MARK: - Actions - Rows

    /// The height a tab row may not fall below.
    ///
    /// The accessibility bump is keyed on touch, not on the text size alone: a
    /// pointer shell holds its rows to one exact height so the list stays a
    /// scannable column, while a touch row is already a hit target and has to
    /// grow with the label rather than clip it.
    func rowMinHeight(dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        guard supportsTouch, dynamicTypeSize.isAccessibilitySize
        else { return CrestLayout.sidebarRowHeight }
        return Self.accessibilityTouchRowHeight
    }
}
