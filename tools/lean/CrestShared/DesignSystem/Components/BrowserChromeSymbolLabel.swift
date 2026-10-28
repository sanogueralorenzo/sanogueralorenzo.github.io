import SwiftUI

/// One SF Symbol geometry for adjacent browser chrome buttons. The shared
/// button style owns the hit frame, keeping every symbol centered without
/// platform-view offsets or custom baselines.
struct BrowserChromeSymbolLabel: View {
    /// The point size adjacent chrome symbols share.
    nonisolated static let defaultPointSize: CGFloat = 14

    let systemName: String
    var pointSize = Self.defaultPointSize

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: .regular))
    }
}

#if DEBUG
    #Preview("Chrome symbols") {
        HStack {
            BrowserChromeSymbolLabel(systemName: "arrow.left")
            BrowserChromeSymbolLabel(systemName: "arrow.right")
            BrowserChromeSymbolLabel(systemName: "arrow.clockwise")
            BrowserChromeSymbolLabel(systemName: "sidebar.left")
        }.padding()
    }
#endif
