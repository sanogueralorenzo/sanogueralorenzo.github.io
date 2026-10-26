import SwiftUI

struct BrowserUtilityListRow: View {
    let item: BrowserUtilityListItem
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions

    @Environment(\.browserFavicons) private var favicons

    var body: some View {
        // List can gather row identities without resolving every row's branch.
        VStack(alignment: .leading, spacing: 0) {
            switch item {
            case .archive(let archived):
                Button {
                    actions.restoreArchivedTab(archived.tab.id, assignment)
                } label: {
                    BrowserUtilityListRowLabel(
                        title: archived.tab.shownTitle,
                        subtitle: archiveSubtitle(archived),
                        subtitleStyle: AnyShapeStyle(
                            archived.reason.tint.color
                        )
                    ) {
                        TabFaviconView(
                            subject: BrowserTabFaviconSubject(
                                tab: archived.tab, image: favicons?.icon(of: archived.tab.id)),
                            profileID: assignment.profileID
                        )
                    } trailing: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restore \(archived.tab.shownTitle)")
                .accessibilityIdentifier(
                    BrowserTabAccessibilityID.archivedRow(archived.tab.id)
                )

            case .history(let entry):
                Button {
                    actions.openHistoryEntry(entry, assignment)
                } label: {
                    BrowserUtilityListRowLabel(
                        title: entry.title,
                        subtitle: historySubtitle(entry)
                    ) {
                        Image(systemName: "globe")
                    } trailing: {
                        Image(systemName: "arrow.up.forward")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(entry.title)")
                .accessibilityIdentifier(
                    BrowserUtilityAccessibilityID.historyRow(entry.id)
                )

            case .download(let download):
                BrowserUtilityDownloadRow(
                    download: download,
                    assignment: assignment,
                    actions: actions
                )
            }
        }
        .crestHoverSurface(
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
    }

    private func archiveSubtitle(_ archived: ArchivedTabState) -> Text {
        let icon = Image(systemName: archived.reason.symbol)
        let status = Text(archived.reason.title)
        if let host = archived.tab.url.flatMap(URL.init(string:))?.host() {
            return Text("\(icon) \(status) · \(host)")
        }
        return Text("\(icon) \(status)")
    }

    private func historySubtitle(_ entry: HistoryEntryState) -> Text {
        let host = URL(string: entry.url)?.host() ?? entry.url
        guard entry.visitCount > 1 else { return Text(host) }
        return Text(
            BrowserUtilityPresentation.historyVisits(
                host: host,
                count: entry.visitCount
            )
        )
    }

}

private struct BrowserUtilityDownloadRow: View {
    let download: DownloadState
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions

    @Environment(\.browserFavicons) private var favicons

    var body: some View {
        HStack(spacing: 0) {
            if let primaryDestination {
                Button {
                    perform(.open(download.id, primaryDestination))
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .browserDownloadFileDrag(download)
                .accessibilityLabel(Text(primaryDestination.title))
                .accessibilityValue(Text(verbatim: accessibilitySummary))
            } else {
                label
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: download.filename))
                    .accessibilityValue(Text(verbatim: accessibilitySummary))
            }

            BrowserDownloadRowAction(
                item: download,
                destinations: actions.downloadDestinations,
                perform: perform
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            BrowserUtilityAccessibilityID.downloadRow(download.id)
        )
    }

    private var label: some View {
        BrowserDownloadRowLabel(download: download)
    }

    private var primaryDestination: BrowserUtilityDownloadDestination? {
        BrowserUtilityDownloadDestination.primary(
            for: download.phase,
            among: actions.downloadDestinations
        )
    }

    private func perform(_ action: BrowserUtilityDownloadAction) {
        actions.performDownloadAction(action, assignment)
    }

    private var accessibilitySummary: String {
        let presentation = BrowserDownloadRowPresentation.resolve(item: download)
        var components = [presentation.statusText.resolvedForSearch()]
        if presentation.showsTransferMetrics {
            components.append(accessibilityTransferMetrics(presentation))
        }
        if let bytesPerSecond = presentation.bytesPerSecond {
            let rate = Int64(bytesPerSecond.rounded()).formatted(
                .byteCount(style: .file)
            )
            components.append(String(localized: "\(rate) per second"))
        }
        if let estimatedTimeRemaining = presentation.estimatedTimeRemaining {
            components.append(
                String(
                    localized: "\(etaLabel(estimatedTimeRemaining)) remaining"
                )
            )
        }
        return components.joined(separator: ", ")
    }

    private func accessibilityTransferMetrics(
        _ presentation: BrowserDownloadRowPresentation
    ) -> String {
        let received = presentation.bytesReceived.formatted(
            .byteCount(style: .file)
        )
        guard let totalBytes = presentation.totalBytes else {
            return String(localized: "\(received) downloaded")
        }
        let total = totalBytes.formatted(.byteCount(style: .file))
        let progress = presentation.progress.formatted(
            .percent.precision(.fractionLength(0))
        )
        return String(
            localized: "\(received) of \(total), \(progress)"
        )
    }

    private func etaLabel(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(
                allowed: [.hours, .minutes, .seconds],
                width: .abbreviated,
                maximumUnitCount: 2
            )
        )
    }

}

private struct BrowserDownloadRowLabel: View {
    let download: DownloadState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            BrowserDownloadStatusIcon(item: download)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(download.filename)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                details
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CrestSpacing.extraSmall)
        .padding(.vertical, CrestSpacing.small)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
    }

    @ViewBuilder
    private var details: some View {
        let presentation = BrowserDownloadRowPresentation.resolve(item: download)
        switch presentation.layout(
            availableWidth: availableWidth,
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        ) {
        case .singleLine:
            primaryLine(presentation)
        case .inline:
            HStack(spacing: 6) {
                primaryLine(presentation)
                Text("·").foregroundStyle(.tertiary)
                secondaryLine(presentation)
            }
            .lineLimit(1)
        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                primaryLine(presentation)
                secondaryLine(presentation)
            }
        }
    }

    private func primaryLine(
        _ presentation: BrowserDownloadRowPresentation
    ) -> Text {
        guard presentation.showsTransferMetrics else {
            return styledStatus(presentation)
        }
        guard let totalBytes = presentation.totalBytes else {
            return Text(
                "\(presentation.bytesReceived, format: .byteCount(style: .file)) downloaded"
            )
            .foregroundStyle(.secondary)
        }
        return Text(
            "\(presentation.bytesReceived, format: .byteCount(style: .file)) of \(totalBytes, format: .byteCount(style: .file)) · \(presentation.progress, format: .percent.precision(.fractionLength(0)))"
        )
        .foregroundStyle(.secondary)
    }

    private func secondaryLine(
        _ presentation: BrowserDownloadRowPresentation
    ) -> Text {
        if let bytesPerSecond = presentation.bytesPerSecond {
            if let estimatedTimeRemaining = presentation.estimatedTimeRemaining {
                return Text(
                    "\(Int64(bytesPerSecond.rounded()), format: .byteCount(style: .file))/s · \(etaLabel(estimatedTimeRemaining)) remaining"
                )
                .foregroundStyle(.secondary)
            }
            return Text(
                "\(Int64(bytesPerSecond.rounded()), format: .byteCount(style: .file))/s"
            )
            .foregroundStyle(.secondary)
        }
        if let estimatedTimeRemaining = presentation.estimatedTimeRemaining {
            return Text(
                "\(etaLabel(estimatedTimeRemaining)) remaining"
            )
            .foregroundStyle(.secondary)
        }
        return styledStatus(presentation)
    }

    private func styledStatus(
        _ presentation: BrowserDownloadRowPresentation
    ) -> Text {
        if presentation.statusNeedsAttention {
            return presentation.statusText.view.foregroundStyle(.red)
        }
        return presentation.statusText.view.foregroundStyle(.secondary)
    }

    private func etaLabel(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(
                allowed: [.hours, .minutes, .seconds],
                width: .abbreviated,
                maximumUnitCount: 2
            )
        )
    }
}
