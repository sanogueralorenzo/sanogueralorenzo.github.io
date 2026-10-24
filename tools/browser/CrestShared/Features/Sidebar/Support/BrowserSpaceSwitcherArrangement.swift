import SwiftUI

/// How the Space switcher lays its Spaces out.
///
/// The two shells reach the switcher differently rather than styling the same
/// control differently: one is a strip at the foot of a windowed sidebar with
/// room for chrome on either side of it, the other is the primary way a finger
/// moves between Spaces and has to stay reachable however many there are. The
/// arrangement names that difference so the switcher can pick one instead of
/// asking which target compiled it.
enum BrowserSpaceSwitcherArrangement: Equatable, Sendable {
    /// A fixed strip of segments flanked by the shell's own accessories. Every
    /// Space is on screen at once, which only holds where the segments can be
    /// small enough for a pointer.
    case compactStrip

    /// A horizontally scrolling segmented control that centres the selected
    /// Space. Segments sized for a finger run out of room quickly, so the
    /// track scrolls and a flick steps through it.
    case scrollingSegments
}

/// The sidebar row rules that follow from what the shell can do.
///
/// Every rule reads the capabilities and nothing else, so a
/// row never asks which target compiled it and a shell that gains or loses an
/// input changes its rows by changing one value at the root.
