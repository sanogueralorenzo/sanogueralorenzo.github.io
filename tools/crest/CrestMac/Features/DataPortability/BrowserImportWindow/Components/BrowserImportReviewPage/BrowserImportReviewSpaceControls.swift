import SwiftUI

struct BrowserImportReviewChecklist: View {
    let flow: BrowserImportFlow
    let application: ImportSource?
    let review: BrowserImportSpaceReview
    let analysis: BrowserImportReviewAnalysis

    var body: some View {
        VStack(spacing: 0) {
            spaceRow
            Divider()
            tabsRow

            if !review.extensions.isEmpty {
                Divider()
                extensionsRow
            }
        }
        .background(
            CrestBrandTheme.canvas.opacity(0.08), in: .rect(cornerRadius: CrestRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrestRadius.card, style: .continuous)
                .strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
        }
        .overlay(alignment: .bottom) {
            if isOutOfRoom {
                Text("No room for another Space")
                    .font(CrestTypography.sans(11, weight: .medium))
                    .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
                    .offset(y: 22)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What \(review.sourceSpace.settings.name) brings")
    }

    // MARK: - Rows

    private var spaceRow: some View {
        BrowserImportReviewRow(
            isOn: spaceInclusion, canToggle: !isOutOfRoom, accessibilityLabel: "Bring this Space"
        ) {
            Text(review.sourceSpace.settings.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            BrowserImportReviewDestinationMenu(
                spaces: flow.destinationSpaces,
                destination: destination,
                destinationName: flow.destinationName(for: review.destination)
            )
            .disabled(!review.isIncluded)
        }
    }

    private var tabsRow: some View {
        BrowserImportReviewRow(isOn: tabInclusion, accessibilityLabel: "Bring its tabs") {
            VStack(alignment: .leading, spacing: 1) {
                Text(BrowserImportSummary.tabCount(review.includedTabIDs.count))
                if overflowCount > 0 {
                    Text(BrowserImportSummary.overflowCount(overflowCount))
                        .font(CrestTypography.sans(11, weight: .medium))
                        .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
                }
            }
        }
        .disabled(!review.isIncluded)
    }

    private var extensionsRow: some View {
        BrowserImportReviewRow(
            isOn: extensionInclusion, accessibilityLabel: "Install extensions for \(review.sourceSpace.settings.name)"
        ) {
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    BrowserImportSummary.extensionCount(
                        included: review.includedExtensionIDs.count, total: review.extensions.count))
                Text(review.extensions.map(\.name).joined(separator: ", "))
                    .font(CrestTypography.sans(11, weight: .medium))
                    .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .disabled(!review.isIncluded)
    }

    // MARK: - Choices

    /// The Space would come in new, but Crest holds no more new Spaces.
    private var isOutOfRoom: Bool {
        !review.isIncluded && review.destination == .newSpace && (flow.review?.newSpaceCapacity ?? 1) == 0
    }

    /// The Space's pinned tabs that move to a saved folder.
    private var overflowCount: Int {
        analysis.overflowTabIDs.intersection(review.includedTabIDs).count
    }

    private var destination: Binding<BrowserImportDestination> {
        Binding(get: { review.destination }, set: { flow.setDestination($0, for: review.id) })
    }

    private var spaceInclusion: Binding<Bool> {
        Binding(get: { review.isIncluded }, set: { flow.setSpaceIncluded($0, in: review.id) })
    }

    /// Every tab the Space holds, on while any of them comes in.
    private var tabInclusion: Binding<Bool> {
        Binding(
            get: { !review.includedTabIDs.isEmpty },
            set: { flow.setIncluded(Set(review.sourceSpace.tabs.models.map(\.id)), $0, in: review.id) })
    }

    private var extensionInclusion: Binding<Bool> {
        Binding(get: { !review.includedExtensionIDs.isEmpty }, set: { flow.setExtensionsIncluded($0, in: review.id) })
    }
}

/// One row of the checklist: a checkbox and what it brings.
private struct BrowserImportReviewRow<Content: View>: View {
    @Binding var isOn: Bool
    /// Whether the checkbox may change; the rest of the row stays usable.
    var canToggle = true
    let accessibilityLabel: LocalizedStringResource
    @ViewBuilder let content: Content
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isOn) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!canToggle)
                .accessibilityLabel(Text(accessibilityLabel))
            HStack(spacing: 8) { content }
                .font(CrestTypography.sans(14, weight: .semibold))
                .foregroundStyle(CrestBrandTheme.textDisplay)
                .opacity(isEnabled ? 1 : 0.55)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

/// Where the Space goes: a new Space, or one Crest already has.
private struct BrowserImportReviewDestinationMenu: View {
    let spaces: [SpaceModel]
    @Binding var destination: BrowserImportDestination
    let destinationName: String

    var body: some View {
        Menu {
            Picker("Destination Space", selection: $destination) {
                Text("New Space").tag(BrowserImportDestination.newSpace)
                ForEach(spaces) { space in
                    BrowserSpaceIdentityLabel(space: space).tag(BrowserImportDestination.existing(space.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                if let space = spaces.first(where: { destination.spaceID == $0.id }) {
                    BrowserSpaceIdentityLabel(space: space, iconSize: 16)
                } else {
                    Text("New Space")
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(CrestTypography.sans(12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                CrestBrandTheme.canvas.opacity(0.1), in: .rect(cornerRadius: CrestRadius.compact, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
                    .strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Where this Space goes")
        .accessibilityValue(destinationName)
    }
}
