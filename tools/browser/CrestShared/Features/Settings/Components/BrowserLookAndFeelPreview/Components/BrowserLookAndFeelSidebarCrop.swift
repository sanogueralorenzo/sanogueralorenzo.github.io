import SwiftUI

/// The window these settings change: the sidebar in full, and beside it as much
/// page as the crop has room for.
///
/// The sidebar is the shipping one at the sidebar's real width, and the page
/// takes every remaining point the way it does in a window. When the column is
/// shorter than the sidebar's contents, the whole window scales down uniformly
/// so all of it stays in view; given room, it returns to real size and the page
/// and atmosphere fill the rest. Moving the sidebar to the other edge slides it
/// across the crop, with the page giving way underneath, as the window does.
struct BrowserLookAndFeelSidebarCrop: View {
    var space: BrowserSpaceAppearance?

    @AppStorage(BrowserChromeAppearancePreference.sidebarOnRightKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarOnRight = BrowserLookAndFeelDefaults.sidebarOnRight
    @AppStorage(BrowserChromeAppearancePreference.borderWidthKey, store: BrowserChromeAppearancePreference.defaults)
    private var borderWidth = BrowserLookAndFeelDefaults.windowBorderWidth

    private var pageZoom = BrowserDefaultPageZoomStore.shared
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The sidebar's natural height, measured before any scaling.
    @State private var sidebarContentHeight: CGFloat = 0

    // Swift versions before 6.4 make the synthesized initializer private because of pageZoom.
    init(space: BrowserSpaceAppearance? = nil) {
        self.space = space
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = Self.scale(fitting: sidebarContentHeight, in: geometry.size.height)
            let designWidth = geometry.size.width / scale
            let designHeight = max(sidebarContentHeight, geometry.size.height / scale)
            window(width: designWidth, height: designHeight, scale: scale)
                .frame(width: designWidth, height: designHeight)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipShape(.rect(cornerRadius: BrowserLookAndFeelPreviewMetrics.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserLookAndFeelPreviewMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(CrestOpacity.border))
        }
        .environment(\.colorScheme, branding.colorScheme(over: colorScheme))
        .animation(
            CrestMotion.collection.unlessReducingMotion(reduceMotion),
            value: sidebarOnRight
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Browser window preview")
        .accessibilityValue(Text(stateDescription))
    }

    /// How far the window shrinks so the sidebar's contents fit the column. It
    /// never grows past real size.
    static func scale(fitting contentHeight: CGFloat, in height: CGFloat) -> CGFloat {
        guard contentHeight > 0, height > 0, contentHeight > height else { return 1 }
        return height / contentHeight
    }

    /// The sidebar keeps the width a real window gives it; only the page grows
    /// as the crop widens. A crop too narrow for that shrinks the sidebar
    /// instead of losing the page edge.
    static func sidebarWidth(in width: CGFloat) -> CGFloat {
        min(
            BrowserChromeLayout.sidebarIdealWidth,
            max(0, width - BrowserLookAndFeelPreviewMetrics.pageMinimumWidth)
        )
    }

    private func window(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let sidebarWidth = Self.sidebarWidth(in: width)
        return ZStack(alignment: edge == .leading ? .topLeading : .topTrailing) {
            HStack(spacing: 0) {
                Color.clear.frame(width: edge == .leading ? sidebarWidth : 0)
                page(scale: scale)
                Color.clear.frame(width: edge == .trailing ? sidebarWidth : 0)
            }
            sidebar
                .frame(width: sidebarWidth)
                .background {
                    travellingAtmosphere(cropWidth: width, sidebarWidth: sidebarWidth)
                }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background {
            BrowserSpaceBannerBackground(branding: branding)
        }
    }

    /// Hugs its own height, as the shipping sidebar does above its empty space,
    /// so folders and tabs are drawn at the size they really are — and reports
    /// that height so the crop knows how far to scale.
    private var sidebar: some View {
        VStack(spacing: CrestSpacing.small) {
            BrowserLookAndFeelAddressPreview(space: space, showsBackground: false)
                .padding(.horizontal, CrestSpacing.small)
            BrowserSidebarCustomizationPreview(space: space, showsBackground: false)
        }
        .padding(.top, CrestSpacing.medium)
        .padding(.bottom, CrestSpacing.large)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { sidebarContentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The sidebar's own slice of the atmosphere, so it slides as a solid panel
    /// instead of its tabs drifting over the page.
    ///
    /// It is the whole crop's atmosphere, drawn at the crop's size and shifted
    /// by the sidebar's position, so at rest it lines up with the background
    /// behind it to the pixel; while the sidebar travels, the shift animates
    /// with it and the panel stays opaque.
    private func travellingAtmosphere(cropWidth: CGFloat, sidebarWidth: CGFloat) -> some View {
        BrowserSpaceBannerBackground(branding: branding)
            .frame(width: cropWidth)
            .offset(x: edge == .leading ? 0 : -(cropWidth - sidebarWidth))
            .frame(width: sidebarWidth, alignment: .leading)
            .clipped()
    }

    private func page(scale: CGFloat) -> some View {
        let appearance = pageAppearance(scale: scale)
        return BrowserRootContentSurface(
            cornerRadius: appearance.pageCornerRadius,
            seamWidth: appearance.seamWidth,
            frameInsets: appearance.pageInsets(docked: true, direction: layoutDirection),
            usesTransparentInnerSurface: false,
            showsBoundary: !appearance.borderless
        ) {
            VStack(spacing: 0) {
                BrowserSettingsPagePreview(zoom: BrowserLookAndFeelPreviewMetrics.pageZoom * pageZoom.defaultZoom)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(white: 0.98))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var appearance: BrowserChromeAppearance {
        BrowserChromeAppearance(sidebarOnRight: sidebarOnRight, borderWidth: borderWidth)
    }

    /// The crop's own corner is the window corner its page follows, so a framed
    /// page stays concentric with it on every device. The crop is clipped after
    /// the window is scaled, so in the window's units that corner is rounder by
    /// the same factor.
    private func pageAppearance(scale: CGFloat) -> BrowserChromeAppearance {
        var appearance = self.appearance
        appearance.windowCornerRadius = BrowserLookAndFeelPreviewMetrics.cardCornerRadius / scale
        return appearance
    }

    private var edge: HorizontalEdge { appearance.sidebarEdge(in: layoutDirection) }

    private var branding: SpaceBranding {
        space?.branding ?? SpaceHouse.winter.look
    }

    private var stateDescription: String {
        let side =
            appearance.sidebarOnRight
            ? String(localized: "Sidebar on right") : String(localized: "Sidebar on left")
        let frame =
            appearance.borderless ? String(localized: "Borderless") : String(localized: "Bordered")
        return "\(side), \(frame)"
    }
}
