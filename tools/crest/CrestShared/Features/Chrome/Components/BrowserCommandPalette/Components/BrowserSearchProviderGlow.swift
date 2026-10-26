import SwiftUI

/// The palette card's glow in the brand color of the provider it searches:
/// a soft halo outside its edge and a fine line on it, which Reduce
/// Transparency and Increase Contrast keep to the line alone.
struct BrowserSearchProviderGlow: ViewModifier {
    let color: BrandColor?
    /// The card's outline, which the glow follows as the card morphs.
    let shape: RoundedRectangle

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    static func showsHalo(reduceTransparency: Bool, contrast: ColorSchemeContrast) -> Bool {
        !reduceTransparency && contrast != .increased
    }

    func body(content: Content) -> some View {
        content
            .background {
                if let color, Self.showsHalo(reduceTransparency: reduceTransparency, contrast: contrast) {
                    shape.stroke(
                        color.color.mix(with: .primary, by: colorScheme == .dark ? 0.2 : 0).opacity(0.65),
                        lineWidth: 3
                    )
                    .blur(radius: 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay {
                if let color {
                    shape.strokeBorder(
                        contrast == .increased
                            ? Color.primary : color.color.mix(with: .primary, by: 0.2).opacity(0.65),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}
