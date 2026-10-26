import SwiftUI

/// Bars along the bottom of a tab while its page plays sound. Where the
/// engine measures the sound, each bar follows its frequency band; elsewhere
/// the bars move on their own. The shell hosts the bars' layer, which takes
/// each measure directly and lets the render server move the bars, so SwiftUI
/// does no work while they move. With Reduce Motion the bars hold still and
/// nothing is measured.
struct BrowserTabEqualizer: View {
    // MARK: - Variables

    let color: Color
    /// The engine's measure of the page's sound, where it measures it.
    let spectrum: BrowserAudioSpectrumFeed?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrowserPlatformTabEqualizer(color: color, isMoving: !reduceMotion, spectrum: reduceMotion ? nil : spectrum)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
