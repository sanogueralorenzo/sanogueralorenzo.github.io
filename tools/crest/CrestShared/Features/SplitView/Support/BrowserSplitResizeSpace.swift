import SwiftUI

/// The coordinate space a divider drag is measured in: the columns row itself.
///
/// A divider handle is positioned from the very fractions its drag writes, so
/// the handle's own frame travels with the boundary it moves. A gesture left in
/// the default `.local` space is re-projected through that travelling frame on
/// every event, which makes the translation it reports the pointer's travel
/// *minus* the handle's — a closed loop. The boundary then chases the pointer at
/// half rate, and pointer noise as small as a point is amplified into a standing
/// oscillation that never settles.
///
/// The row is the nearest ancestor that does not move when fractions change, so
/// measuring there is what makes a drag report the pointer's real travel and
/// track it one to one. `BrowserSplitColumnsView` declares the space on the row;
/// `BrowserSplitCardResizeHandle` measures in it.
enum BrowserSplitResizeSpace {
    static let name = "crest.split-view.columns"

    static var coordinateSpace: NamedCoordinateSpace {
        .named(name)
    }
}
