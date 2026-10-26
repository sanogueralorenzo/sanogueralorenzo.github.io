import SwiftUI

struct BrowserSoftwareUpdateSidebarWidget: View {
    // MARK: - Variables

    let instance: BrowserSidebarWidgetInstance
    let update: BrowserSoftwareUpdateWidgetSnapshot
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void

    @Environment(\.browserSoftwareUpdateDetails) private var showDetails

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserSidebarWidgetDeckStyle.contentSpacing) {
            headerRow
            progressZone
            actions
        }
        .overlay(alignment: .topTrailing) {
            hideButton
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crest software update")
    }

    private var canHide: Bool {
        instance.availableActions.contains(.hideSoftwareUpdate)
    }

    /// The card's own buttons, without the corner control that hides it.
    private var buttonActions: Set<BrowserSidebarWidgetAction> {
        instance.availableActions.subtracting([.hideSoftwareUpdate])
    }

    // MARK: - Actions - Layout

    private var headerRow: some View {
        HStack(alignment: .top, spacing: CrestSpacing.small) {
            BrowserSoftwareUpdateApplicationIcon()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                HStack(spacing: CrestSpacing.extraSmall) {
                    headerTitle
                        .font(.subheadline.weight(.semibold))
                    if update.isFixture {
                        Text("TEST")
                            .font(CrestTypography.badge)
                            .padding(.horizontal, CrestSpacing.extraSmall)
                            .padding(
                                .vertical,
                                BrowserSidebarWidgetDeckStyle.badgeVerticalPadding
                            )
                            .background(
                                .orange.opacity(CrestOpacity.brandHairline),
                                in: .capsule
                            )
                            .accessibilityLabel("Test fixture")
                    }
                }
                .lineLimit(1)

                if let versionLine {
                    Text(verbatim: versionLine)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if hasDetails, let showDetails {
                    Button("What's New") { showDetails() }
                        .buttonStyle(.plain)
                        .font(CrestTypography.metadata.weight(.medium))
                        .foregroundStyle(CrestBrandTheme.accent)
                        .accessibilityLabel("Review update details")
                        .help("Review update details")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(
                .trailing,
                canHide ? BrowserSidebarWidgetDeckStyle.quietControlDiameter + CrestSpacing.extraSmall : 0
            )
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var hideButton: some View {
        if canHide {
            Button {
                perform(.hideSoftwareUpdate, instance.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(BrowserSidebarWidgetQuietControlStyle(alignment: .topTrailing))
            .accessibilityLabel("Hide Update")
            .help("Hide until you check for updates")
        }
    }

    @ViewBuilder
    private var progressZone: some View {
        if let progress = update.progress, update.phase.isTransferring {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(CrestBrandTheme.accent)
                .accessibilityLabel(Text(statusLabel))
        } else if update.phase.isWorking {
            HStack(spacing: CrestSpacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text(statusLabel)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(statusLabel))
        }

        if let message = update.message, update.phase.showsMessage {
            Text(verbatim: message)
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !buttonActions.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CrestSpacing.small) {
                    actionButtons
                }
                VStack(spacing: CrestSpacing.small) {
                    actionButtons
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if instance.availableActions.contains(.declineAutomaticUpdateChecks) {
            actionButton(
                .declineAutomaticUpdateChecks,
                label: "Not Now",
                symbol: "clock",
                emphasis: .quiet
            )
        }

        if instance.availableActions.contains(.dismissExactUpdate) {
            actionButton(
                .dismissExactUpdate,
                label: "Skip",
                symbol: "forward.end",
                accessibilityLabel: "Skip This Version",
                emphasis: .quiet
            )
        }

        if instance.availableActions.contains(.viewUpdateInformation),
            let informationURL = update.informationURL
        {
            Link(destination: informationURL) {
                Label("View Release", systemImage: "arrow.up.right")
            }
            .buttonStyle(
                BrowserSidebarWidgetActionButtonStyle(
                    emphasis: .prominent
                )
            )
        } else if instance.availableActions.contains(.installUpdate) {
            actionButton(
                .installUpdate,
                label: "Download",
                symbol: "arrow.down.circle",
                accessibilityLabel: "Download Update",
                emphasis: .prominent
            )
        } else if instance.availableActions.contains(.installAndRelaunch) {
            actionButton(
                .installAndRelaunch,
                label: "Restart",
                symbol: "arrow.down.to.line",
                accessibilityLabel: "Restart and Update",
                emphasis: .prominent
            )
        } else if instance.availableActions.contains(.cancelUpdate) {
            actionButton(
                .cancelUpdate,
                label: "Cancel",
                symbol: "xmark",
                emphasis: .quiet
            )
        } else if instance.availableActions.contains(.retryUpdateInstallation) {
            actionButton(
                .retryUpdateInstallation,
                label: "Retry",
                symbol: "arrow.clockwise",
                accessibilityLabel: "Try Quitting Again",
                emphasis: .prominent
            )
        } else if instance.availableActions.contains(.enableAutomaticUpdateChecks) {
            actionButton(
                .enableAutomaticUpdateChecks,
                label: "Check Automatically",
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                emphasis: .prominent
            )
        } else if instance.availableActions.contains(.acknowledgeUpdateStatus) {
            actionButton(
                .acknowledgeUpdateStatus,
                label: "Dismiss",
                symbol: "xmark",
                emphasis: .quiet
            )
        }
    }

    private func actionButton(
        _ action: BrowserSidebarWidgetAction,
        label: LocalizedStringKey,
        symbol: String,
        accessibilityLabel: LocalizedStringKey? = nil,
        emphasis: BrowserSidebarWidgetActionEmphasis
    ) -> some View {
        Button {
            perform(action, instance.id)
        } label: {
            Label(label, systemImage: symbol)
        }
        .buttonStyle(BrowserSidebarWidgetActionButtonStyle(emphasis: emphasis))
        .accessibilityLabel(accessibilityLabel ?? label)
        .help(accessibilityLabel ?? label)
    }

    private var hasDetails: Bool {
        if let releaseNotes = update.releaseNotes, !releaseNotes.isEmpty {
            return true
        }
        return update.informationURL != nil
    }

    private var headerTitle: Text {
        update.phase.isTitledByUpdate ? Text(verbatim: update.title) : Text(update.phase.title)
    }

    private var versionLine: String? {
        switch (update.version, update.build) {
        case (let version?, let build?) where version != build:
            "Version \(version) · Build \(build)"
        case (let version?, _):
            "Version \(version)"
        case (_, let build?):
            "Build \(build)"
        default:
            nil
        }
    }

    private var statusLabel: LocalizedStringResource {
        (update.isInformationOnly ? update.phase.informationOnlyStatusLabel : nil) ?? update.phase.statusLabel
    }
}

private struct BrowserSoftwareUpdateApplicationIcon: View {
    @Environment(\.browserApplicationIcon) private var applicationIcon

    var body: some View {
        (applicationIcon ?? Image(systemName: "app.fill"))
            .resizable()
            .scaledToFit()
            .frame(
                width: BrowserSidebarWidgetDeckStyle.headerTileSize,
                height: BrowserSidebarWidgetDeckStyle.headerTileSize
            )
    }
}

extension EnvironmentValues {
    /// Opens the full release notes for the update a card presents. Nil where
    /// the shell has no window to show them in, which leaves out What's New.
    @Entry var browserSoftwareUpdateDetails: BrowserSoftwareUpdateDetailsAction? = nil
}
