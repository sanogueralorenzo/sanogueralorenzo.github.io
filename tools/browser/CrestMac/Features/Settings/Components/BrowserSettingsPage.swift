import AppKit
import SwiftUI

/// Compact, consistent page chrome. Each pane owns its scrolling surface.
struct BrowserSettingsPage<Content: View>: View {
    let destination: BrowserSettingsDestination
    let back: BrowserSettingsPageBack?
    @ViewBuilder let content: Content

    init(
        destination: BrowserSettingsDestination,
        back: BrowserSettingsPageBack? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.back = back
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if destination != .spaces {
                BrowserSettingsCompactPageIdentity(destination: destination, back: back)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(BrowserSettingsCanvas.background)
        .controlSize(.regular)
    }
}

/// The way back from a sub-page to the page that leads to it.
struct BrowserSettingsPageBack {
    let title: LocalizedStringResource
    let action: () -> Void
}
