import SwiftUI

struct BrowserSitePermissionRecordRow: View {
    let record: SitePermissionRecordState
    let permissionCenter: BrowserSitePermissionCenter

    var body: some View {
        HStack(spacing: CrestFormRowMetrics.contentSpacing) {
            Image(systemName: record.permission.symbol)
                .frame(width: BrowserPrivacySettingsLayout.permissionIconWidth)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                Text(record.siteName)
                    .lineLimit(1)
                Text(record.displayLabel)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: CrestSpacing.small)

            Menu(record.decision.title) {
                Group {
                    if !record.permission.isAskedBySystem {
                        Button("Allow", systemImage: "checkmark.circle") {
                            set(.grantPersistently)
                        }
                    }
                    Button("Block", systemImage: "nosign") {
                        set(.denyPersistently)
                    }
                    Divider()
                    Button(
                        "Ask Again",
                        systemImage: "arrow.counterclockwise",
                        role: .destructive
                    ) {
                        permissionCenter.reset(recordID: record.id)
                    }
                }
                .crestMenuActionLabelStyle()
            }
            .crestMenuActionLabelStyle()
            .modifier(BrowserPlatformSitePermissionMenuModifier())
            .accessibilityLabel(
                "\(record.displayLabel) for \(record.siteName)"
            )
            .accessibilityValue(Text(record.decision.title))
        }
        .frame(minHeight: CrestFormRowMetrics.minimumHeight)
    }

    private func set(_ decision: SitePermissionDecision) {
        permissionCenter.setDecision(
            decision,
            for: record.permission,
            origin: record.origin,
            detail: record.detail,
            in: record.spaceID
        )
    }
}
