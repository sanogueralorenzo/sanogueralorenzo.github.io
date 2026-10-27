import SwiftUI

struct CrestSurfaceLayer<LayerShape: Shape>: View {
    let shape: LayerShape
    var hoverTint: Color? = nil

    var body: some View {
        shape.fill(CrestBrandTheme.surface)
            .overlay { if let hoverTint { shape.fill(hoverTint) } }
    }
}
