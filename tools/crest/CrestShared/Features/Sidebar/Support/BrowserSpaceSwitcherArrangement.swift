import SwiftUI

/// The Space selector's arrangement for pointer or touch input.
enum BrowserSpaceSwitcherArrangement: Equatable, Sendable {
    /// A compact scrolling strip of segments sized for a pointer.
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
