import SwiftUI

struct BrowserStartPage: View {
    let store: BrowserStore
    var body: some View {
        VStack(spacing: 28) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 48, height: 48)
            Text("Start Page").font(.system(size: 24, weight: .semibold))
            AddressPalette(store: store, standalone: true)
        }
    }
}
