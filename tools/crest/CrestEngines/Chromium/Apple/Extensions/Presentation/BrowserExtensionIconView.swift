import SwiftUI

struct BrowserExtensionIconView: View {
    let image: NSImage?
    var size: CGFloat = BrowserExtensionsMetrics.extensionIconSize
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "puzzlepiece.extension.fill").resizable().scaledToFit()
                    .padding(size * BrowserExtensionsMetrics.extensionIconFallbackPaddingRatio)
                    .foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .clipShape(
            .rect(cornerRadius: size * BrowserExtensionsMetrics.extensionIconCornerRadiusRatio, style: .continuous))
    }
}
