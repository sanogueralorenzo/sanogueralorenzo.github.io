import SwiftUI

/// The sidebar's back, forward, and reload strip, on every shell.
///
/// Everything the strip needs from the page layer arrives through
/// `BrowserSidebarNavigationPort`, and everything about how it is drawn comes
/// from `BrowserInteractionCapabilities` — so the two shells share this strip
/// rather than a resemblance. What is left is one slot at the trailing end for
/// a shell that keeps its page menu there.
struct BrowserSidebarNavigationControls<TrailingAccessory: View>: View {
    private let port: BrowserSidebarNavigationPort
    private let capabilities: BrowserInteractionCapabilities
    private let hidesUnavailableForwardControl: Bool
    private let trailingAccessory: TrailingAccessory

    /// - Parameter hidesUnavailableForwardControl: Whether the forward control
    ///   leaves the strip entirely when there is nowhere to go. This is a shell's
    ///   own choice rather than something its inputs decide: a strip that has
    ///   room for a permanently disabled chevron keeps it where the reader
    ///   learned it, and one that does not would rather spend the width.
    init(
        port: BrowserSidebarNavigationPort,
        capabilities: BrowserInteractionCapabilities,
        hidesUnavailableForwardControl: Bool = false,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory = {
            EmptyView()
        }
    ) {
        self.port = port
        self.capabilities = capabilities
        self.hidesUnavailableForwardControl = hidesUnavailableForwardControl
        self.trailingAccessory = trailingAccessory()
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        strip
            .labelStyle(.iconOnly)
            .buttonStyle(
                CrestChromeButtonStyle(controlSize: metrics.controlSize)
            )
            .padding(.leading, metrics.leadingInset)
            .padding(.trailing, metrics.trailingInset)
            .padding(.vertical, verticalPadding)
            .modifier(
                BrowserSidebarNavigationControlBand(
                    height: metrics.barHeight,
                    growsWithContent: metrics.growsWithContent
                )
            )
    }

    private var strip: some View {
        HStack(spacing: metrics.controlSpacing) {
            Spacer(minLength: metrics.leadingSpacerMinimum)

            BrowserSidebarNavigationHistoryControl(
                direction: .back,
                port: port,
                metrics: metrics
            )

            if showsForwardControl {
                BrowserSidebarNavigationHistoryControl(
                    direction: .forward,
                    port: port,
                    metrics: metrics
                )
            }

            BrowserReloadControl(
                isLoading: port.isLoading(),
                isDeveloperMode: port.activeURL()?.isLocalDevelopmentAddress == true,
                reloadOrStop: port.reloadOrStop,
                reload: port.reload,
                reloadFromOrigin: port.reloadFromOrigin,
                clearCookiesAndReload: port.clearCookiesAndReload,
                isEnabled: port.hasActivePage(),
                reloadControlSize: metrics.controlSize,
                menuControlSize: metrics.reloadMenuControlSize,
                symbolPointSize: metrics.reloadSymbolPointSize
            )

            trailingAccessory
        }
    }

    private var showsForwardControl: Bool {
        !hidesUnavailableForwardControl || port.canGoForward()
    }

    private var verticalPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? metrics.accessibilityVerticalPadding
            : 0
    }

    private var metrics: BrowserSidebarNavigationControlMetrics {
        capabilities.navigationControlMetrics
    }
}
