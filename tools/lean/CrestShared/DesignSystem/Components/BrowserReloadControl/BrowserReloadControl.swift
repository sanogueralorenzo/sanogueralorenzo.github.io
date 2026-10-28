import SwiftUI

/// One reload interaction shared by compact address bars and the persistent
/// iPad/macOS sidebar chrome. Local developer pages keep their reload options
/// inline on touch and in a context menu in the compact pointer strip.
struct BrowserReloadControl: View {
    let isLoading: Bool
    let isDeveloperMode: Bool
    let reloadOrStop: () -> Void
    let reload: () -> Void
    let reloadFromOrigin: () -> Void
    let clearCookiesAndReload: () async -> Void
    var isEnabled = true
    var reloadControlSize = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var menuControlSize = CGSize(
        width: CrestLayout.minimumHitTarget,
        height: CrestLayout.minimumHitTarget
    )
    var symbolPointSize = BrowserChromeSymbolLabel.defaultPointSize
    var showsDeveloperMenuInline = true

    @Environment(\.browserShortcutBindings) private var bindings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reloadPulse = 0
    @State private var isPlayingReloadFeedback = false
    @State private var isClearingSiteData = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: performPrimaryAction) {
                VStack(spacing: CrestSpacing.extraExtraSmall) {
                    BrowserReloadFeedbackIcon(
                        systemName: symbolName,
                        pulse: reloadPulse,
                        animates: !reduceMotion,
                        pointSize: symbolPointSize,
                        feedbackDidComplete: finishReloadFeedback
                    )
                    BrowserShortcutHint(shortcut: primaryCommand.shortcut(in: bindings))
                }
                .frame(minWidth: reloadControlSize.width, minHeight: reloadControlSize.height)
            }
            .buttonStyle(CrestChromeButtonStyle(controlSize: nil))
            .accessibilityLabel(isLoading ? "Stop" : "Reload")
            .accessibilityIdentifier("reload-control")
            .help(isLoading ? "Stop" : "Reload")
            .contextMenu {
                if isDeveloperMode && !showsDeveloperMenuInline { developerActions }
            }

            if isDeveloperMode && showsDeveloperMenuInline {
                Menu {
                    developerActions
                } label: {
                    Image(systemName: isClearingSiteData ? "progress.indicator" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(
                            width: menuControlSize.width,
                            height: menuControlSize.height
                        )
                        .contentShape(.rect)
                }
                .crestMenuActionLabelStyle()
                .menuIndicator(.hidden)
                .menuStyle(.button)
                .buttonStyle(CrestChromeButtonStyle(controlSize: menuControlSize))
                .accessibilityLabel("Reload options")
                .accessibilityIdentifier("developer-reload-menu")
                .help("Reload Options")
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(
            isEnabled
                ? Color.secondary
                : Color.secondary.opacity(CrestOpacity.controlDisabledForeground)
        )
        .disabled(!isEnabled)
    }

    private var developerActions: some View {
        Group {
            Button("Reload", systemImage: "arrow.clockwise") {
                performAnimatedReload(reload)
            }
            Button(
                "Reload (Ignore Cache)",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            ) {
                performAnimatedReload(reloadFromOrigin)
            }
            Divider()
            Button(
                "Clear Cookies, Storage, and Reload",
                systemImage: "trash"
            ) {
                clearAndReload()
            }
            .disabled(isClearingSiteData)
        }
        .crestMenuActionLabelStyle()
    }

    private var primaryCommand: ShortcutCommand { isLoading ? .stopLoading : .reloadPage }

    /// Stop while a load runs, unless the reload feedback is still turning.
    private var symbolName: String {
        isLoading && !isPlayingReloadFeedback ? "xmark" : "arrow.clockwise"
    }

    private func performPrimaryAction() {
        guard !isLoading else {
            reloadOrStop()
            return
        }
        performAnimatedReload(reloadOrStop)
    }

    private func performAnimatedReload(_ action: () -> Void) {
        beginReloadFeedback()
        action()
    }

    private func clearAndReload() {
        guard !isClearingSiteData else { return }
        isClearingSiteData = true
        beginReloadFeedback()
        Task { @MainActor in
            await clearCookiesAndReload()
            isClearingSiteData = false
        }
    }

    private func beginReloadFeedback() {
        isPlayingReloadFeedback = !reduceMotion
        reloadPulse += 1
    }

    private func finishReloadFeedback(_ completedPulse: Int) {
        guard completedPulse == reloadPulse else { return }
        isPlayingReloadFeedback = false
    }
}

#if DEBUG
    #Preview("Reload, stop, and developer menu") {
        @Previewable @State var loading = false
        VStack {
            BrowserReloadControl(
                isLoading: loading, isDeveloperMode: true, reloadOrStop: { loading.toggle() },
                reload: { loading = true }, reloadFromOrigin: { loading = true }, clearCookiesAndReload: {})
            Toggle("Loading", isOn: $loading)
        }.padding().frame(width: 240)
    }
#endif
