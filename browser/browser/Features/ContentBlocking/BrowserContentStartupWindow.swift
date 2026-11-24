import AppKit
import SwiftUI

@MainActor
final class BrowserContentStartupWindow: NSWindowController, NSWindowDelegate {
    enum Phase {
        case downloading
        case preparing
        case failed
    }

    @Observable final class State {
        var phase: Phase

        init(phase: Phase) { self.phase = phase }
    }

    let state: State

    init(phase: Phase) {
        state = State(phase: phase)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Browser Setup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Content(state: state))
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    private struct Content: View {
        let state: State

        var body: some View {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                switch state.phase {
                case .downloading:
                    progress("Downloading content blocking…")
                case .preparing:
                    progress(BrowserContentBlocking.preparingLabel)
                case .failed:
                    Text("Content blocking couldn’t be set up.")
                    Text("Browser will try again the next time it opens.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Quit Browser") { NSApp.terminate(nil) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 12)
        }

        private func progress(_ label: String) -> some View {
            ProgressView(label)
                .progressViewStyle(.linear)
                .frame(width: 238)
        }
    }
}
