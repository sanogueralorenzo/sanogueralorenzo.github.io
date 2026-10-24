import SwiftUI

/// The sidebar's hover area, filled with the system accent while someone
/// adjusts its width and fading out about three seconds after the last change.
///
/// It is drawn behind the strip itself, so it only shows where the strip is and
/// never takes input: the strip and the page underneath keep answering the
/// pointer.
struct BrowserSidebarRevealZonePreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0
    @State private var fade: Task<Void, Never>?

    private let preview = SidebarRevealWidthPreview.shared

    var body: some View {
        Color.accentColor
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: preview.adjustmentCount) { restartFade() }
            .onDisappear { fade?.cancel() }
    }

    /// Full strength straight away, then gone three seconds after the last
    /// adjustment. Reduce Motion holds it and removes it without the fade.
    private func restartFade() {
        fade?.cancel()
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { opacity = 1 }
        fade = Task {
            if reduceMotion {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                opacity = 0
            } else {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 2.5)) { opacity = 0 }
            }
        }
    }
}
