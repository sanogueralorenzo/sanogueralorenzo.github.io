import SwiftUI

struct CrestStartPageMarkPalette {
    let background: Color
    let rail: Color
    let butter: Color
    let sky: Color
    let coral: Color

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    private static let light = CrestStartPageMarkPalette(
        background: Color(red: 0.969, green: 0.965, blue: 0.949),
        rail: Color(red: 0.149, green: 0.227, blue: 0.302),
        butter: Color(red: 0.957, green: 0.824, blue: 0.482),
        sky: Color(red: 0.498, green: 0.686, blue: 0.808),
        coral: Color(red: 0.937, green: 0.439, blue: 0.369)
    )

    private static let dark = CrestStartPageMarkPalette(
        background: Color(red: 0.082, green: 0.125, blue: 0.169),
        rail: Color(red: 0.929, green: 0.941, blue: 0.949),
        butter: Color(red: 0.969, green: 0.839, blue: 0.435),
        sky: Color(red: 0.447, green: 0.722, blue: 0.871),
        coral: Color(red: 0.949, green: 0.416, blue: 0.341)
    )

    private init(
        background: Color,
        rail: Color,
        butter: Color,
        sky: Color,
        coral: Color
    ) {
        self.background = background
        self.rail = rail
        self.butter = butter
        self.sky = sky
        self.coral = coral
    }
}
