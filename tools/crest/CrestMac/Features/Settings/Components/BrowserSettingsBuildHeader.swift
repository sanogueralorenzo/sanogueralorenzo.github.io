import AppKit
import SwiftUI

/// The build at a glance over the Settings sidebar, in the icon the person
/// chose and with the engine the build runs pages in.
struct BrowserSettingsBuildHeader: View {
    @Environment(\.browserMacWindows) private var windows

    var body: some View {
        BrowserSettingsBuildSummary(engine: windows?.engineCredits) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }
}
