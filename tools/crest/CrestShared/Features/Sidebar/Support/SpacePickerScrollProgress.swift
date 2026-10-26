import SwiftUI

/// Keeps manual overflow scrolling continuous when paging takes over the icon lane.
struct SpacePickerScrollProgress {
    let generation: UInt
    let phase: SpacePagerPresentation.Phase
    let destinationID: UUID
    let startPosition: CGFloat
    let destinationPosition: CGFloat
    let startOffset: CGFloat
    let destinationOffset: CGFloat

    func offset(at position: CGFloat) -> CGFloat {
        let distance = destinationPosition - startPosition
        guard abs(distance) > 0.000_001 else { return startOffset }
        let fraction = min(1, max(0, (position - startPosition) / distance))
        return startOffset + (destinationOffset - startOffset) * fraction
    }
}
