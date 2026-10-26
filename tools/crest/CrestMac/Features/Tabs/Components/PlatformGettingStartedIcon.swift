import AppKit
import SwiftUI

struct PlatformGettingStartedIcon: View {
    @Environment(\.browserApplicationIcon) private var applicationIcon

    var body: some View {
        (applicationIcon ?? Image(nsImage: NSApplication.shared.applicationIconImage))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}
