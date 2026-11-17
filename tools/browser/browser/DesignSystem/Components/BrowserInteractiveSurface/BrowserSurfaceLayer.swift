import SwiftUI

struct BrowserSurfaceLayer<LayerShape: Shape>: View {
    let shape: LayerShape
    var tint: Color? = nil
    var hoverTint: Color? = nil

    var body: some View {
        shape.fill(BrowserBrandTheme.surface)
            .overlay { if let tint { shape.fill(tint) } }
            .overlay { if let hoverTint { shape.fill(hoverTint) } }
    }
}
