import SwiftUI

extension BrandColor {
    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
    static let neutral = BrandColor(red: 0.5, green: 0.5, blue: 0.5)
}
