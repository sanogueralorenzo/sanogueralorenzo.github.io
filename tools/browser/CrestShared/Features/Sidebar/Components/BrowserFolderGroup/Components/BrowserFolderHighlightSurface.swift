import SwiftUI

extension EnvironmentValues {
    @Entry var folderPreviewShowsHighlight = false
    @Entry var folderUsesContrastingForeground = false
    @Entry var folderBackgroundColor: BrandColor? = nil
}

/// Shared by live folder groups and the inline settings preview.
struct BrowserFolderHighlightSurface: ViewModifier {
    let color: BrandColor
    let intensity: Double
    var textColorMode: SpaceTextColorMode = .automatic
    var showsFill = true
    var showsBorders = true
    /// How many folders hold this one. Each steps the surface in by the
    /// container padding and rounds it one padding tighter, concentric with
    /// the folder around it.
    var depth = 0
    var isSelected = false
    var emphasisOpacity: Double = 0

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.folderBackgroundColor) private var parentBackgroundColor

    private var foregroundScheme: ColorScheme {
        if let override = textColorMode.foregroundTone(system: BrowserSpaceForegroundTone(readingIn: colorScheme)) {
            return override == .light ? .dark : .light
        }
        guard showsFill, intensity > 0 else { return colorScheme }
        return compositedColor.foregroundTone.colorScheme
    }

    private var compositedColor: BrandColor {
        let channel = colorScheme == .dark ? 0.0 : 1.0
        return color.composited(
            opacity: fillOpacity,
            over: parentBackgroundColor ?? BrandColor(red: channel, green: channel, blue: channel))
    }

    private var fillOpacity: Double {
        let strength = intensity.isFinite ? min(max(intensity, 0), 1) : 0
        let baseline = reduceTransparency ? 0.28 : 0.12
        return baseline + (1 - baseline) * strength
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth), style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                if showsFill {
                    CrestSurfaceLayer(shape: shape, tint: color.color.opacity(fillOpacity))
                        .overlay {
                            if emphasisOpacity > 0 { shape.fill(.primary.opacity(emphasisOpacity)) }
                        }
                        .overlay {
                            if isSelected { shape.fill(CrestColor.hover) }
                        }
                        .overlay {
                            if showsBorders {
                                shape.strokeBorder(color.color.opacity(0.5), lineWidth: 1)
                            }
                        }
                        .padding(.leading, BrowserFolderLayout.surfaceLeadingInset(depth: depth))
                        .padding(.trailing, BrowserSidebarMetrics.layerInset)
                        .allowsHitTesting(false)
                }
            }
            .environment(\.colorScheme, foregroundScheme)
            .environment(\.folderUsesContrastingForeground, textColorMode != .automatic || showsFill)
            .environment(\.folderBackgroundColor, showsFill ? compositedColor : parentBackgroundColor)
    }
}
