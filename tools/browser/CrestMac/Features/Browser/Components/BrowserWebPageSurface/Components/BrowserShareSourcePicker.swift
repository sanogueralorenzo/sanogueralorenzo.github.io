import AppKit
import SwiftUI

/// Asks which of the offered tabs the page shares, or whether the system's
/// picker asks for a window or a display instead, on the same lifted panel
/// as the page's permission and credential prompts. It stays over the page
/// until the person answers or the engine withdraws the offer.
struct BrowserShareSourcePicker: View {
    // MARK: - Variables

    let offer: BrowserShareSourceOffer
    /// The page that asks, whose own tab the list names as this tab.
    let requestingPageID: UUID
    /// Where the tab holding a page sits in its Space and what it is called,
    /// so the list follows the sidebar.
    let tabPlacement: (UUID) -> BrowserShareSourceOffer.TabPlacement?
    /// The name of the page that asks, as its tab is called.
    let requestingTabName: String
    let answer: (BrowserShareSourceOffer.Choice) -> Void

    @State private var selection: UUID?
    @State private var sharesAudio = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserWebPageSurfaceMetrics.sharePickerSpacing) {
            header
            tabs
            if offer.asksAudio {
                Toggle(isOn: $sharesAudio) {
                    Text(
                        "Also share tab audio",
                        comment: "Screen sharing picker option to include the shared tab's sound.")
                }
                .font(.caption)
                .toggleStyle(.checkbox)
            }
            actions
        }
        .padding(BrowserWebPageSurfaceMetrics.sharePickerPadding)
        .frame(width: BrowserWebPageSurfaceMetrics.sharePickerWidth, alignment: .leading)
        .background {
            CrestSurfaceLayer(shape: panelShape)
        }
        .overlay {
            panelShape.strokeBorder(.separator, lineWidth: BrowserWebPageSurfaceMetrics.sharePickerStrokeWidth)
        }
        .shadow(
            color: .black.opacity(reduceTransparency ? 0 : CrestOpacity.controlShadow),
            radius: BrowserWebPageSurfaceMetrics.sharePickerShadowRadius,
            y: BrowserWebPageSurfaceMetrics.sharePickerShadowOffset
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text("Choose what to share", comment: "Accessibility label for the screen sharing picker.")
        )
        .accessibilityAddTraits(.isModal)
        .padding(BrowserWebPageSurfaceMetrics.overlayPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onExitCommand { answer(.cancel) }
    }

    // MARK: - Actions - Layout

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BrowserWebPageSurfaceMetrics.sharePickerCornerRadius, style: .continuous)
    }

    /// The site that asks and what it wants, as a permission prompt names
    /// them, and the way out.
    private var header: some View {
        HStack(alignment: .top, spacing: BrowserWebPageSurfaceMetrics.sharePickerHeaderSpacing) {
            Image(systemName: SitePermission.screenSharing.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(
                    width: BrowserWebPageSurfaceMetrics.sharePickerHeaderIconSize,
                    height: BrowserWebPageSurfaceMetrics.sharePickerHeaderIconSize
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrowserWebPageSurfaceMetrics.sharePickerHeaderTextSpacing) {
                Text(requestingTabName.isEmpty ? offer.site : requestingTabName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SitePermission.screenSharing.requestTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                answer(.cancel)
            } label: {
                Label {
                    Text("Don't Share", comment: "Screen sharing picker control that shares nothing.")
                } icon: {
                    Image(systemName: "xmark")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(
                CrestChromeButtonStyle(
                    controlSize: CGSize(
                        width: BrowserWebPageSurfaceMetrics.sharePickerCloseControlSize,
                        height: BrowserWebPageSurfaceMetrics.sharePickerCloseControlSize))
            )
            .keyboardShortcut(.cancelAction)
        }
    }

    private var tabs: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrowserWebPageSurfaceMetrics.sharePickerListRowSpacing) {
                ForEach(offer.tabsInSidebarOrder(placement: tabPlacement)) { tab in
                    BrowserShareSourceTabRow(
                        tab: tab, isRequestingTab: tab.id == requestingPageID, isSelected: selection == tab.id
                    ) {
                        selection = tab.id
                    }
                }
            }
        }
        .frame(maxHeight: BrowserWebPageSurfaceMetrics.sharePickerListMaximumHeight)
        // Rows pad out so their highlight reaches past the text. The list,
        // and the area it clips its rows to, widens by that much, so the
        // text lines up with the header and every highlight keeps its shape.
        .padding(.horizontal, -BrowserWebPageSurfaceMetrics.sharePickerRowHighlightBleed)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tabs", comment: "Accessibility label for the list of tabs a page can share."))
    }

    private var actions: some View {
        HStack(spacing: CrestSpacing.small) {
            Button {
                answer(.windowOrScreen)
            } label: {
                Text("Window or Screen…", comment: "Screen sharing picker button that opens the system picker.")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                if let selection { answer(.tab(pageID: selection, audio: offer.asksAudio && sharesAudio)) }
            } label: {
                Text("Share Tab", comment: "Screen sharing picker button that shares the selected tab.")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selection == nil)
        }
        .controlSize(.large)
    }
}

/// One tab the page can share: its icon, its title, and the site it shows,
/// highlighted as the browser's other rows are under the pointer and when
/// chosen.
private struct BrowserShareSourceTabRow: View {
    // MARK: - Variables

    let tab: BrowserShareSourceOffer.Tab
    /// Whether the tab is the page that asks.
    let isRequestingTab: Bool
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: BrowserWebPageSurfaceMetrics.sharePickerRowSpacing) {
                icon
                    .frame(
                        width: BrowserWebPageSurfaceMetrics.sharePickerRowIconSize,
                        height: BrowserWebPageSurfaceMetrics.sharePickerRowIconSize
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrowserWebPageSurfaceMetrics.sharePickerRowTextSpacing) {
                    Text(tab.displayTitle)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isRequestingTab {
                        Text("This Tab", comment: "Screen sharing picker note on the tab of the page that asks.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let host = tab.url?.host(), !host.isEmpty, host != tab.displayTitle {
                        Text(host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: CrestSpacing.small)
                Image(systemName: "checkmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrowserWebPageSurfaceMetrics.sharePickerRowHighlightBleed)
            .padding(.vertical, BrowserWebPageSurfaceMetrics.sharePickerRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(BrowserShareSourceTabRowStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Actions - Layout

    @ViewBuilder private var icon: some View {
        if let data = tab.icon, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        }
    }
}

private struct BrowserShareSourceTabRowStyle: ButtonStyle {
    // MARK: - Variables

    let isSelected: Bool

    // MARK: - Actions - Layout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .crestHoverSurface(
                isSelected: isSelected,
                cornerRadius: BrowserWebPageSurfaceMetrics.sharePickerRowHighlightCornerRadius,
                isPressed: configuration.isPressed
            )
    }
}

#if DEBUG
    #Preview("Tabs to share") {
        let callID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        BrowserShareSourcePicker(
            offer: BrowserShareSourceOffer(
                id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9)),
                site: "meet.example",
                tabs: [
                    .init(id: callID, title: "Weekly sync", url: URL(string: "https://meet.example"), icon: nil),
                    .init(
                        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)), title: "Q4 roadmap",
                        url: URL(string: "https://docs.example"), icon: nil),
                    .init(
                        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)), title: "Release checklist",
                        url: URL(string: "https://code.example"), icon: nil),
                ],
                asksAudio: true),
            requestingPageID: callID,
            tabPlacement: { _ in nil },
            requestingTabName: "Weekly sync",
            answer: { _ in }
        )
        .frame(width: 480, height: 420)
    }
#endif
