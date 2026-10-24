import SwiftUI

/// The restrained paper-and-ink palette shared by Crest's public identity and
/// first-party app surfaces. Space colors remain user-owned and more expressive.
enum CrestBrandPalette {
    static let inkComponents = CrestColorComponents(red: 23, green: 34, blue: 56)
    static let inkSoftComponents = CrestColorComponents(red: 39, green: 54, blue: 83)
    static let paperComponents = CrestColorComponents(red: 255, green: 250, blue: 240)
    static let parchmentComponents = CrestColorComponents(red: 243, green: 234, blue: 214)
    static let butterComponents = CrestColorComponents(red: 231, green: 189, blue: 88)
    static let coralComponents = CrestColorComponents(red: 237, green: 90, blue: 67)
    static let sageComponents = CrestColorComponents(red: 129, green: 155, blue: 121)
    static let skyComponents = CrestColorComponents(red: 98, green: 169, blue: 216)

    static let ink = inkComponents.color
    static let inkSoft = inkSoftComponents.color
    static let paper = paperComponents.color
    static let parchment = parchmentComponents.color
    static let butter = butterComponents.color
    static let coral = coralComponents.color
    static let sage = sageComponents.color
    static let sky = skyComponents.color
    static let match = sage
    static let line = ink.opacity(CrestOpacity.brandHairline)
}
