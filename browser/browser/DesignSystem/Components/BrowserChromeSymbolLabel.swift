import SwiftUI

struct BrowserChromeSymbolLabel: View {
    nonisolated static let defaultPointSize: CGFloat = 14

    let systemName: String
    var pointSize = Self.defaultPointSize

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: .regular))
    }
}
