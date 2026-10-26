import SwiftUI

/// The browser chrome follows system appearance, with monochrome surfaces.
enum CrestBrandTheme {
    // MARK: - Static Variables

    static let accent = textDisplay
    static let accentText = textDisplay
    static let canvas = dynamic(light: .init(red: 255, green: 255, blue: 255), dark: .init(red: 0, green: 0, blue: 0))
    static let surface = dynamic(
        light: .init(red: 242, green: 242, blue: 242), dark: .init(red: 24, green: 24, blue: 24))
    static let textDisplay = dynamic(
        light: .init(red: 0, green: 0, blue: 0), dark: .init(red: 255, green: 255, blue: 255))
    static let line = textDisplay.opacity(0.18)

    // MARK: - Actions - Appearance

    static func accent(_ colorScheme: ColorScheme) -> Color { textDisplay(colorScheme) }
    static func accentText(_ colorScheme: ColorScheme) -> Color { textDisplay(colorScheme) }
    static func canvas(_ colorScheme: ColorScheme) -> Color { colorScheme == .dark ? .black : .white }
    static func surface(_ colorScheme: ColorScheme) -> Color {
        Color(white: colorScheme == .dark ? 24.0 / 255 : 242.0 / 255)
    }
    static func textDisplay(_ colorScheme: ColorScheme) -> Color { colorScheme == .dark ? .white : .black }
    static func line(_ colorScheme: ColorScheme) -> Color { textDisplay(colorScheme).opacity(0.18) }

    private static func dynamic(light: CrestColorComponents, dark: CrestColorComponents) -> Color {
        CrestPlatformDynamicColor.make(light: light, lightOpacity: 1, dark: dark, darkOpacity: 1)
    }
}
