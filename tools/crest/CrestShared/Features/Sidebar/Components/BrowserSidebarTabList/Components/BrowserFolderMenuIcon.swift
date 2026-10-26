import SwiftUI

/// Native menus flatten styled SF Symbols into template images. Supply one
/// original-color image so the destination matches its folder in the sidebar.
struct BrowserFolderMenuIcon: View {
    let systemName: String
    let color: BrandColor

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let symbol = Image(systemName: systemName)
            .font(.system(size: 14))
            .foregroundStyle(color.color)
            .frame(width: 18, height: 18)
            .environment(\.colorScheme, colorScheme)
        if let image = artwork(for: symbol) {
            image.renderingMode(.original)
        } else {
            symbol
        }
    }

    private func artwork(for content: some View) -> Image? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale
        guard let image = renderer.cgImage else { return nil }
        return Image(decorative: image, scale: displayScale)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserFolderMenuIcon(systemName: "folder.fill", color: .ocean).padding()
    }
#endif
