import SwiftUI

extension BrowserSpaceForegroundTone {
    // MARK: - Variables

    /// The color scheme whose text draws in this tone: light text reads as a
    /// dark scheme.
    var colorScheme: ColorScheme {
        self == .light ? .dark : .light
    }

    // MARK: - Initializers

    /// The tone text reads in under `colorScheme`: a dark scheme reads light.
    init(readingIn colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .light : .dark
    }
}
