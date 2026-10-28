import SwiftUI

/// Returns a durable tab to its saved address, then puts its page to sleep.
/// Current tabs keep their close control.
struct BrowserSidebarTabTrailingControl: View {
    @Environment(\.browserShortcutBindings) private var shortcutBindings

    let configuration: BrowserSidebarTabRowConfiguration
    @Binding var isHovering: Bool

    @ViewBuilder
    var body: some View {
        if configuration.tab.placement.isDurable {
            HStack(spacing: CrestSpacing.extraSmall) {
                if configuration.isSelected {
                    BrowserShortcutHint(shortcut: ShortcutCommand.closeTabOrWindow.shortcut(in: shortcutBindings))
                }
                if configuration.canReturnToSavedAddress || configuration.isLoaded {
                    Button(action: performDurableAction) {
                        BrowserSidebarTabTrailingControlLabel(
                            systemName: configuration.canReturnToSavedAddress ? "arrow.uturn.backward" : "minus",
                            metrics: configuration.trailingControlMetrics
                        )
                    }
                    .modifier(BrowserSidebarTabTrailingControlStyle(metrics: configuration.trailingControlMetrics))
                    .disabled(
                        !configuration.isAvailableForDisplay
                            || (configuration.canReturnToSavedAddress
                                ? configuration.context.restoreSavedLocation == nil : !configuration.isLoaded)
                    )
                    .accessibilityLabel(durableActionTitle)
                    .accessibilityIdentifier(
                        configuration.canReturnToSavedAddress ? "return-tab-to-saved-url" : "sleep-saved-tab"
                    )
                    .help(durableActionTitle)
                }
            }
        } else {
            HStack(spacing: CrestSpacing.extraSmall) {
                if configuration.isSelected {
                    BrowserShortcutHint(shortcut: ShortcutCommand.closeTabOrWindow.shortcut(in: shortcutBindings))
                }
                BrowserSidebarTabCloseButton(
                    configuration: configuration,
                    isVisible: configuration.canClose && isRevealed
                )
            }
        }
    }

    private var durableActionTitle: LocalizedStringKey {
        configuration.canReturnToSavedAddress ? "Return to Saved URL" : "Put Tab to Sleep"
    }

    private var isRevealed: Bool {
        configuration.trailingControlMetrics.isRevealed(
            isHovering: isHovering,
            isSelected: configuration.isSelected
        )
    }

    private func performDurableAction() {
        guard configuration.isCurrentAndAvailable else { return }
        if configuration.canReturnToSavedAddress {
            configuration.context.restoreSavedLocation?(configuration.tab.id)
        } else if configuration.isLoaded,
            BrowserDurableTabCloseAction(browser: configuration.browser).perform(configuration.runtimeAssignment)
        {
            configuration.context.pageAccess.selectPages()
        }
    }

}

private struct BrowserSidebarTabCloseButton: View {
    @Environment(CrestCore.self) private var core: CrestCore?
    let configuration: BrowserSidebarTabRowConfiguration
    let isVisible: Bool

    var body: some View {
        Button {
            guard configuration.isCurrentAndAvailable else { return }
            configuration.browser.closeTab(
                configuration.tab.id,
                matching: configuration.assignment
            )
        } label: {
            BrowserSidebarTabTrailingControlLabel(
                systemName: "xmark",
                metrics: metrics
            )
        }
        .modifier(BrowserSidebarTabTrailingControlStyle(metrics: metrics))
        .contentShape(.circle)
        .foregroundStyle(Color.primary)
        .opacity(
            isVisible
                ? metrics.closeOpacity(isSelected: configuration.isSelected)
                : 0
        )
        .disabled(!configuration.canClose || !configuration.isAvailableForDisplay)
        .allowsHitTesting(isVisible)
        .accessibilityLabel("Close \(configuration.tab.shownTitle(in: configuration.isLoaded ? core?.state : nil))")
    }

    private var metrics: BrowserTabTrailingControlMetrics {
        configuration.trailingControlMetrics
    }
}

private struct BrowserSidebarTabTrailingControlLabel: View {
    let systemName: String
    let metrics: BrowserTabTrailingControlMetrics

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: metrics.glyphSize, weight: metrics.glyphWeight))
            .frame(
                width: metrics.controlSize.width,
                height: metrics.controlSize.height
            )
            .contentShape(.circle)
    }
}

/// The chrome's hover-and-press treatment where a pointer can earn it, and a
/// plain button where nothing can.
private struct BrowserSidebarTabTrailingControlStyle: ViewModifier {
    let metrics: BrowserTabTrailingControlMetrics

    @ViewBuilder
    func body(content: Content) -> some View {
        if metrics.usesChromeControlStyle {
            content.buttonStyle(
                CrestChromeButtonStyle(
                    controlSize: metrics.controlSize, cornerRadius: metrics.cornerRadius, cornerStyle: .circular)
            )
        } else {
            content.buttonStyle(.plain)
        }
    }
}
