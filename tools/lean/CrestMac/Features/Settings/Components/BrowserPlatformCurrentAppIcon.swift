import SwiftUI

struct BrowserPlatformCurrentAppIcon: View {
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
            .resizable().scaledToFit()
    }
}
