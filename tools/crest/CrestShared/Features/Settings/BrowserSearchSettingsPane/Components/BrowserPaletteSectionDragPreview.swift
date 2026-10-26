import SwiftUI

/// What follows the pointer while a person drags one of the palette's
/// sections: its handle and name on the row's surface.
struct BrowserPaletteSectionDragPreview: View {
    let source: PaletteSource

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Text(source.title)
        }
        .padding(.horizontal, CrestSpacing.medium)
        .padding(.vertical, CrestSpacing.small)
        .background {
            CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.compact, style: .continuous))
        }
    }
}
