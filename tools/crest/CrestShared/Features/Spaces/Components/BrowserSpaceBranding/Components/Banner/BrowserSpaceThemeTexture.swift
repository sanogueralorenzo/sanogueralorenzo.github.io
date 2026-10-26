import SwiftUI

struct BrowserSpaceThemeTexture: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let sampleCount = min(20_000, max(800, Int(size.width * size.height / 24)))
            var generator = BrowserSpaceTextureGenerator(seed: 0xC2E5_7A11)
            var lightGrain = Path()
            var darkGrain = Path()

            for index in 0..<sampleCount {
                let x = generator.nextUnit() * size.width
                let y = generator.nextUnit() * size.height
                let diameter = 0.85 + generator.nextUnit() * 1.5
                let particle = CGRect(
                    x: x,
                    y: y,
                    width: diameter,
                    height: diameter
                )
                if index.isMultiple(of: 2) {
                    lightGrain.addEllipse(in: particle)
                } else {
                    darkGrain.addEllipse(in: particle)
                }
            }

            context.fill(lightGrain, with: .color(.white.opacity(0.46)))
            context.fill(darkGrain, with: .color(.black.opacity(0.38)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
