import SwiftUI

extension BrandColor {
    /// The color's name where a person sees it: its tincture's, or Custom.
    var title: LocalizedStringResource {
        tincture?.title ?? "Custom"
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
