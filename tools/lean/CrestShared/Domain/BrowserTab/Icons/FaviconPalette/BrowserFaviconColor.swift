import Foundation

struct BrowserFaviconColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    var iconAccent: BrowserTabIconAccent {
        BrowserTabIconAccent(red: red, green: green, blue: blue)
    }

    var perceptualComponents: SIMD3<Double> {
        let linearRed = Self.linearComponent(red)
        let linearGreen = Self.linearComponent(green)
        let linearBlue = Self.linearComponent(blue)
        let l =
            0.412_221_470_8 * linearRed
            + 0.536_332_536_3 * linearGreen
            + 0.051_445_992_9 * linearBlue
        let m =
            0.211_903_498_2 * linearRed
            + 0.680_699_545_1 * linearGreen
            + 0.107_396_956_6 * linearBlue
        let s =
            0.088_302_461_9 * linearRed
            + 0.281_718_837_6 * linearGreen
            + 0.629_978_700_5 * linearBlue
        let lRoot = cbrt(l)
        let mRoot = cbrt(m)
        let sRoot = cbrt(s)
        return SIMD3(
            0.210_454_255_3 * lRoot + 0.793_617_785 * mRoot - 0.004_072_046_8 * sRoot,
            1.977_998_495_1 * lRoot - 2.428_592_205 * mRoot + 0.450_593_709_9 * sRoot,
            0.025_904_037_1 * lRoot + 0.782_771_766_2 * mRoot - 0.808_675_766 * sRoot
        )
    }

    init(perceptualComponents value: SIMD3<Double>) {
        let lRoot = value.x + 0.396_337_777_4 * value.y + 0.215_803_757_3 * value.z
        let mRoot = value.x - 0.105_561_345_8 * value.y - 0.063_854_172_8 * value.z
        let sRoot = value.x - 0.089_484_177_5 * value.y - 1.291_485_548 * value.z
        let l = lRoot * lRoot * lRoot
        let m = mRoot * mRoot * mRoot
        let s = sRoot * sRoot * sRoot
        self.init(
            red: Self.encodedComponent(
                4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s
            ),
            green: Self.encodedComponent(
                -1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s
            ),
            blue: Self.encodedComponent(
                -0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701 * s
            )
        )
    }

    private static func linearComponent(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encodedComponent(_ value: Double) -> Double {
        value <= 0.003_130_8
            ? 12.92 * value
            : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}
