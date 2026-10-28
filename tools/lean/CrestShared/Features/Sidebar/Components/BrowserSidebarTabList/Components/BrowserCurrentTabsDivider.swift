import SwiftUI

/// The seam between the saved run and the current one, on every shell.
///
/// Pointer-only shells reveal the archive action on hover. Touch shells keep it visible.
struct BrowserCurrentTabsDivider: View {
    // MARK: - Variables

    let capabilities: BrowserInteractionCapabilities
    /// Whether the shell is currently in the state that reveals the control —
    /// a pointer resting somewhere over the list.
    var showsClearAction = false
    /// Whether there is anything left to clear.
    let canClear: Bool
    let clear: () -> Void
    @Environment(\.displayScale) private var displayScale
    @Environment(\.browserShortcutBindings) private var shortcutBindings

    private var metrics: BrowserSidebarTabListMetrics {
        capabilities.tabListMetrics
    }

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            VStack(spacing: 0) {
                Divider()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 1 / displayScale)
            if showsClearButton {
                clearButton
            }
        }
        .frame(height: canClear ? controlHeight : 1 / displayScale)
        .padding(.vertical, verticalInset)
        .padding(.horizontal, metrics.dividerHorizontalInset)
    }

    private var clearButton: some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                if revealsOnHoverOnly {
                    Text("Clear")
                    BrowserShortcutHint(shortcut: ShortcutCommand.clearUnpinnedTabs.shortcut(in: shortcutBindings))
                }
                Image(systemName: "archivebox")
            }
            .padding(.horizontal, CrestSpacing.small)
            .frame(minWidth: capabilities.supportsTouch ? 44 : nil, minHeight: controlHeight)
            .contentShape(.capsule)
        }
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: controlHeight / 2, cornerStyle: .circular)
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityLabel("Archive Current Tabs")
        .accessibilityHint("Moves all current tabs to Archive")
    }

    private var controlHeight: CGFloat {
        capabilities.supportsTouch ? 44 : 28
    }

    private var verticalInset: CGFloat {
        max(0, metrics.dividerVerticalInset - (canClear ? controlHeight / 2 : 0))
    }

    private var showsClearButton: Bool {
        canClear && (!revealsOnHoverOnly || showsClearAction)
    }

    private var revealsOnHoverOnly: Bool {
        capabilities.revealsRowControlsOnHoverOnly
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCurrentTabsDivider(
            capabilities: BrowserInteractionCapabilities(), showsClearAction: true, canClear: true, clear: {}
        ).padding().frame(width: 320)
    }
#endif
