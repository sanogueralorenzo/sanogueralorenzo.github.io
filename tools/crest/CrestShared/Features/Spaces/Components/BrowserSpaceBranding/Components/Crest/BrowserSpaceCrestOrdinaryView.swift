import SwiftUI

/// The band laid over the field, clipped to the plate. A bordure is the plate's
/// own outline drawn inward.
struct BrowserSpaceCrestOrdinaryView: View {
    let ordinary: CrestOrdinary
    var width: Double = 1
    let plate: BrowserSpaceCrestPlateShape
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            if ordinary == .bordure {
                plate.stroke(color, lineWidth: BrowserSpaceCrestOrdinaryPath.bordureWidth(size: size, width: width) * 2)
            } else {
                BrowserSpaceCrestOrdinaryPath(ordinary: ordinary, width: width).fill(color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(plate)
    }
}
