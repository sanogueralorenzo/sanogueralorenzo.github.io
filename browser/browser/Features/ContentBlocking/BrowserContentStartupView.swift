import AppKit
import SwiftUI

struct BrowserContentStartupView: View {
    let phase: BrowserContentStartup.Phase

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Getting Browser ready…")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            switch phase {
            case .downloading:
                progress("Downloading ad blocking…")
            case .preparing:
                progress("Preparing your Space…")
            case .failed:
                Text("Content blocking couldn’t be set up.")
                Text("Browser will try again the next time it opens.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Quit Browser") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .background(BrowserBrandTheme.canvas)
        .ignoresSafeArea()
        .tint(BrowserBrandTheme.textDisplay)
    }

    private func progress(_ label: LocalizedStringKey) -> some View {
        ProgressView(label)
            .progressViewStyle(.linear)
            .frame(width: 238)
    }
}
