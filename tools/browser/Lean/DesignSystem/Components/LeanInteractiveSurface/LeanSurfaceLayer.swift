import SwiftUI

struct LeanSurfaceLayer<LayerShape: Shape>: View {
    let shape: LayerShape
    var hoverTint: Color? = nil

    var body: some View {
        shape.fill(LeanBrandTheme.surface)
            .overlay { if let hoverTint { shape.fill(hoverTint) } }
    }
}
