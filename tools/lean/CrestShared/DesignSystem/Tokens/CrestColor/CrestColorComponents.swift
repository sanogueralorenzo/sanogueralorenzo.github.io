import SwiftUI

struct CrestColorComponents: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var color: Color {
        Color(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}
