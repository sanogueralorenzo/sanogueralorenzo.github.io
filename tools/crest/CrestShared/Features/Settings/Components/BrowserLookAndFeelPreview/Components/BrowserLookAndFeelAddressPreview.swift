import SwiftUI

/// The shipping address field on this Space's atmosphere, holding a friendly
/// sample rather than whatever is open behind the settings window.
struct BrowserLookAndFeelAddressPreview: View {
    var space: BrowserSpaceAppearance?
    var showsBackground = true

    @Namespace private var namespace
    /// The Space a preview without one names. Nothing else lives in the
    /// preview's own namespace, so any stable identity will do.
    @State private var standInSpaceID = UUID()

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if showsBackground {
            field
                .padding(CrestSpacing.medium)
                .frame(maxWidth: .infinity)
                .background { BrowserSpaceBannerBackground(branding: branding) }
                .clipShape(.rect(cornerRadius: BrowserLookAndFeelPreviewMetrics.cardCornerRadius))
                .environment(\.colorScheme, branding.colorScheme(over: colorScheme))
        } else {
            field
        }
    }

    private var field: some View {
        BrowserSidebarAddressField(
            configuration: .init(
                text: .constant(BrowserLookAndFeelPreviewMetrics.sampleAddress),
                isEditing: .constant(false),
                isSecure: true,
                progress: 0,
                isLoading: false,
                capabilities: .init(
                    supportsTouch: capabilities.supportsTouch,
                    pairsRowWithPromotedSurface: false),
                activate: {},
                submit: {},
                morphNamespace: namespace,
                spaceID: space?.id ?? standInSpaceID,
                branding: branding)
        )
        .labelsHidden()
        .frame(maxWidth: BrowserChromeLayout.sidebarMaximumWidth)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Address field preview")
        .accessibilityValue(BrowserLookAndFeelPreviewMetrics.sampleAddress)
    }

    private var branding: SpaceBranding {
        space?.branding ?? SpaceHouse.winter.look
    }
}
