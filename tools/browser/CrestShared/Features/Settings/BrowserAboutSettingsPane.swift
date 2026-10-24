import SwiftUI

struct BrowserAboutSettingsPane: View {
    static let startsWhatsNewExpanded = false

    let buildInformation: BrowserAboutBuildInformation
    let releaseNotes: [BrowserAboutReleaseNote]

    @State private var showsWhatsNew: Bool

    init(
        buildInformation: BrowserAboutBuildInformation = .current,
        releaseNotes: [BrowserAboutReleaseNote] =
            BrowserAboutReleaseNotes.bundled.currentHighlights()
    ) {
        self.buildInformation = buildInformation
        self.releaseNotes = releaseNotes
        _showsWhatsNew = State(initialValue: Self.startsWhatsNewExpanded)
    }

    var body: some View {
        BrowserSettingsPane(.about) {
            Section {
                appIdentity
            }

            BrowserPlatformSoftwareUpdateSettingsSection()

            if !releaseNotes.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsWhatsNew) {
                        VStack(
                            alignment: .leading,
                            spacing: CrestSpacing.medium
                        ) {
                            ForEach(releaseNotes) { releaseNote in
                                BrowserAboutReleaseNoteRow(
                                    releaseNote: releaseNote
                                )
                            }
                        }
                        .padding(.vertical, CrestSpacing.small)
                    } label: {
                        Text("What's New in Crest \(buildInformation.version)")
                            .font(.body.weight(.medium))
                    }
                    .disclosureGroupStyle(
                        BrowserAboutWhatsNewDisclosureStyle()
                    )
                }
            }

            Section {
                BrowserAboutLink(
                    title: "Share Feedback on r/CrestBrowser",
                    imageName: "AboutReddit",
                    destination: BrowserAboutLinks.feedback,
                    identifier: "about-feedback-link"
                )
                BrowserAboutLink(
                    title: "Report an Issue",
                    imageName: "AboutGitHub",
                    destination: BrowserAboutLinks.issues,
                    identifier: "about-issues-link"
                )
                BrowserAboutLink(
                    title: "View the Roadmap",
                    imageName: "AboutGitHub",
                    destination: BrowserAboutLinks.roadmap,
                    identifier: "about-roadmap-link"
                )
            } header: {
                Text("Community and support")
            } footer: {
                CrestFormFootnote("Reddit is public. Leave out private details.")
            }
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 14) {
            BrowserPlatformCurrentAppIcon()
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(ProductIdentity.name)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                // Selectable text is an AppKit view: a label with no value recurses when assistive apps read it.
                Text("Version \(buildInformation.version) (\(buildInformation.build))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Version")
                    .accessibilityValue(
                        Text(
                            "\(buildInformation.version), build \(buildInformation.build), bundle identifier: \(buildInformation.bundleIdentifier)"
                        )
                    )
                    .help(buildInformation.bundleIdentifier)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct BrowserAboutWhatsNewDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: CrestSpacing.small) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(
                            .degrees(configuration.isExpanded ? 90 : 0)
                        )
                        .accessibilityHidden(true)

                    configuration.label

                    Spacer(minLength: CrestSpacing.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("about-whats-new-disclosure")
            .accessibilityValue(
                configuration.isExpanded ? "Expanded" : "Collapsed"
            )
            .accessibilityHint(
                configuration.isExpanded
                    ? "Hides recent changes"
                    : "Shows recent changes"
            )

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

private struct BrowserAboutLink: View {
    let title: LocalizedStringResource
    let imageName: String
    let destination: URL
    let identifier: String

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: CrestSpacing.medium) {
                Image(imageName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: CrestSpacing.small)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct BrowserAboutReleaseNoteRow: View {
    let releaseNote: BrowserAboutReleaseNote

    var body: some View {
        let mark = BrowserAboutReleaseNoteMark.marking(releaseNote.category)
        HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.small) {
            Image(systemName: mark.symbol)
                .foregroundStyle(mark.color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(releaseNote.message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The glyph that marks each kind of release note in What's New.
private struct BrowserAboutReleaseNoteMark: Sendable {
    // MARK: - Static Variables

    static let new = BrowserAboutReleaseNoteMark(category: .new, symbol: "sparkles", color: CrestBrandPalette.sky)
    static let improved = BrowserAboutReleaseNoteMark(
        category: .improved, symbol: "arrow.up.circle.fill", color: CrestBrandPalette.butter)
    static let fixed = BrowserAboutReleaseNoteMark(
        category: .fixed, symbol: "checkmark.circle.fill", color: CrestBrandPalette.sage)
    static let `internal` = BrowserAboutReleaseNoteMark(
        category: .internal, symbol: "wrench.and.screwdriver.fill", color: .secondary)

    /// A mark for every category.
    static let all: [BrowserAboutReleaseNoteMark] = [new, improved, fixed, `internal`]

    // MARK: - Variables

    let category: BrowserAboutReleaseNoteCategory
    let symbol: String
    let color: Color

    // MARK: - Actions - Lookup

    static func marking(_ category: BrowserAboutReleaseNoteCategory) -> BrowserAboutReleaseNoteMark {
        all.first { $0.category == category } ?? .internal
    }
}
