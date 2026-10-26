import SwiftUI

/// Shared settings-navigation label used by the native macOS and mobile shells.
struct CrestSettingsDestinationLabel: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let systemImage: String
    let color: Color
    var compact = false
    var castsShadow = false

    var body: some View {
        HStack(spacing: labelSpacing) {
            CrestIconTile(
                systemImage: systemImage,
                color: color,
                size: iconSize,
                symbolSize: symbolSize,
                cornerRadius: iconCornerRadius,
                castsShadow: castsShadow
            )

            VStack(
                alignment: .leading,
                spacing: CrestSettingsPresentationMetrics.titleSpacing
            ) {
                Text(title)
                    .font(CrestTypography.controlTitle)
                    .foregroundStyle(CrestColor.textPrimary)
                if !compact || BrowserSettingsLayout.showsSidebarSubtitles {
                    Text(subtitle)
                        .font(
                            compact
                                ? CrestTypography.compactMetadata
                                : CrestTypography.metadata
                        )
                        .foregroundStyle(CrestColor.textSecondary)
                        .lineLimit(1)
                }
            }

            if compact {
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle))
    }

    private var labelSpacing: CGFloat {
        compact
            ? CrestSettingsPresentationMetrics.compactLabelSpacing
            : CrestSpacing.medium
    }

    private var iconSize: CGFloat {
        compact
            ? BrowserSettingsLayout.sidebarIconSize
            : CrestSettingsPresentationMetrics.regularIconSize
    }

    private var symbolSize: CGFloat {
        compact
            ? CrestSettingsPresentationMetrics.compactSymbolSize
            : CrestSettingsPresentationMetrics.regularSymbolSize
    }

    private var iconCornerRadius: CGFloat {
        compact
            ? CrestSettingsPresentationMetrics.compactIconCornerRadius
            : CrestSettingsPresentationMetrics.regularIconCornerRadius
    }
}

#if DEBUG
    #Preview("Regular and compact") {
        VStack(alignment: .leading, spacing: 20) {
            CrestSettingsDestinationLabel(
                title: "Appearance", subtitle: "Make Crest your own", systemImage: "paintpalette.fill", color: .indigo)
            CrestSettingsDestinationLabel(
                title: "Privacy", subtitle: "Control your browsing data", systemImage: "hand.raised.fill",
                color: .green, compact: true)
        }.padding().frame(width: 380)
    }
#endif
