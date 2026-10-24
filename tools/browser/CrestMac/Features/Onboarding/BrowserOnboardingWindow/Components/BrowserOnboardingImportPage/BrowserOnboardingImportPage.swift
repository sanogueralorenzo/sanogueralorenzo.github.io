import SwiftUI

/// The browsers on this Mac setup can bring tabs from, as tiles to choose.
struct BrowserOnboardingImportPage: View {
    let sources: [BrowserInstalledImportSource]
    let isSelected: (BrowserInstalledImportSource) -> Bool
    /// Whether the person asked setup to scan, and how many browsers it does
    /// not list the scan found.
    let hasScanned: Bool
    let unlistedCount: Int
    let isReading: Bool
    let isLocked: Bool
    let failure: BrowserOnboardingFailureText?
    let accessLabel: (BrowserInstalledImportSource) -> String?
    let toggleSelection: (BrowserInstalledImportSource) -> Void
    let scanForMore: () -> Void
    let beginManualSetup: () -> Void
    let continueImport: () -> Void
    /// Stops reading the chosen browser, leaving the choice as it was.
    let cancelRead: () -> Void
    let back: BrowserOnboardingBackAction

    private var hasSelection: Bool { sources.contains(where: isSelected) }

    var body: some View {
        VStack(spacing: 0) {
            BrowserOnboardingHeadline("Bring your tabs")
                .padding(.top, 22)
            // The browsers sit centered while they fit, and scroll once they
            // don't, so the footer stays in reach however many are installed.
            ViewThatFits(in: .vertical) {
                choices
                    .frame(maxHeight: .infinity)
                ScrollView { choices }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: .infinity)
            BrowserOnboardingFooter(back: back, isBackDisabled: isLocked) {
                HStack(spacing: 18) {
                    if isReading {
                        // Reading sits where Continue was, with a way out, so a
                        // slow browser never looks like a dead end.
                        ProgressView()
                            .controlSize(.small)
                        Text("Building your review…")
                            .font(CrestTypography.sans(13, weight: .medium))
                            .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.7))
                        Button("Cancel", action: cancelRead)
                            .buttonStyle(.crestSecondary)
                            .accessibilityIdentifier("onboarding-import-cancel")
                    } else {
                        if let failure {
                            Label {
                                BrowserOnboardingFailureMessage(message: failure)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .font(CrestTypography.sans(12, weight: .medium))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .accessibilityIdentifier("onboarding-import-error")
                        }
                        Button("Skip", action: beginManualSetup)
                            .buttonStyle(.crestTertiary)
                            .accessibilityIdentifier("onboarding-import-skip")
                        BrowserOnboardingContinueButton(action: continueImport)
                            .disabled(!hasSelection)
                            .accessibilityIdentifier("onboarding-import-continue")
                    }
                }
                .disabled(isLocked && !isReading)
            }
        }
    }

    private var choices: some View {
        VStack(spacing: 32) {
            if sources.isEmpty, hasScanned {
                ContentUnavailableView(
                    "No Supported Browsers Found",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("You can still set up Spaces by hand.")
                )
            } else if !sources.isEmpty {
                BrowserInstalledImportSourceGrid(
                    sources: sources,
                    isSelected: isSelected,
                    isLocked: isLocked,
                    accessLabel: accessLabel,
                    toggleSelection: toggleSelection
                )
            }

            BrowserOnboardingScanForMore(
                hasScanned: hasScanned,
                foundCount: unlistedCount,
                isLocked: isLocked,
                scan: scanForMore
            )
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

/// Scans the browsers' data on the person's say-so, since macOS may say Crest
/// looked at other apps' data, and says where to ask for a browser the scan
/// cannot find.
private struct BrowserOnboardingScanForMore: View {
    let hasScanned: Bool
    let foundCount: Int
    let isLocked: Bool
    let scan: () -> Void

    var body: some View {
        if !hasScanned {
            Button("Scan for more", systemImage: "magnifyingglass", action: scan)
                .buttonStyle(.crestSecondary)
                .disabled(isLocked)
                .accessibilityHint("Looks through other browsers’ data on this Mac")
                .accessibilityIdentifier("onboarding-import-scan")
        } else {
            VStack(spacing: 6) {
                if foundCount == 0 {
                    Text("Crest couldn’t find another browser. Not every browser can be found.")
                        .font(CrestTypography.sans(13, weight: .medium))
                        .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                Link("Request a browser", destination: BrowserAboutLinks.browserRequest)
                    .font(CrestTypography.sans(13, weight: .bold))
                    .foregroundStyle(CrestBrandTheme.accent)
            }
        }
    }
}
