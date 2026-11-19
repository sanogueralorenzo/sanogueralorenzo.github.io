import AppKit
import SwiftUI

@MainActor
final class BrowserContentStartupWindow: NSWindowController, NSWindowDelegate {
    enum Phase {
        case downloading(Double?)
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

    func setDownloadProgress(_ fraction: Double?) {
        if case .downloading = state.phase { state.phase = .downloading(fraction) }
    }

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
                case .downloading(let fraction):
                    progress(fraction: fraction)
                case .preparing:
                    progress(fraction: nil)
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

        private func progress(fraction: Double?) -> some View {
            let label = BrowserContentBlocking.preparingLabel
            return Group {
                if let fraction {
                    ProgressView(label, value: fraction)
                } else {
                    ProgressView(label)
                }
            }
            .progressViewStyle(.linear)
            .frame(width: 238)
        }
    }
}
