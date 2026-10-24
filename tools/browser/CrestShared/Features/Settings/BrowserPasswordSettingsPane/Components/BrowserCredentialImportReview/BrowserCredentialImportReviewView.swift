import SwiftUI

struct BrowserCredentialImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let initialReviewID: UUID
    let credentials: BrowserCredentialSpaceStore
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    @State private var searchText = ""
    @State private var revealedGroupIDs: Set<BrowserCredentialImportGroupID> = []

    var body: some View {
        NavigationStack {
            Group {
                if let review = credentials.importReview,
                    review.id == initialReviewID,
                    let space = browser.spaceModel(matching: review.destination)
                {
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(
                                alignment: .leading,
                                spacing: CrestSpacing.extraExtraLarge
                            ) {
                                BrowserCredentialImportDestinationCard(
                                    space: space.identity,
                                    format: review.plan.format
                                )
                                BrowserCredentialImportSummaryView(review: review)

                                if !review.groups.isEmpty {
                                    VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                                        BrowserCredentialImportReviewSectionHeader(
                                            title: "Accounts",
                                            detail:
                                                "Review every valid account. Choose which password to keep, or skip any account."
                                        )

                                        BrowserCredentialSearchField(
                                            title: "Search imported passwords",
                                            text: $searchText,
                                            accessibilityIdentifier:
                                                "imported-password-search"
                                        )
                                    }

                                    let matchingGroups = review.groups(matching: searchText)
                                    if matchingGroups.isEmpty {
                                        ContentUnavailableView.search(text: searchText)
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        ForEach(matchingGroups, id: \.reviewID) { group in
                                            BrowserCredentialImportAccountRow(
                                                group: group,
                                                selection: review.selection(for: group),
                                                existingPassword: review.existingPassword(for: group),
                                                revealsPasswords:
                                                    revealedGroupIDs.contains(group.reviewID),
                                                select: { selection in
                                                    credentials.selectImport(
                                                        selection,
                                                        for: group.reviewID
                                                    )
                                                },
                                                togglePasswordVisibility: {
                                                    if !revealedGroupIDs.insert(group.reviewID)
                                                        .inserted
                                                    {
                                                        revealedGroupIDs.remove(group.reviewID)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                }

                                if !review.plan.warnings.isEmpty {
                                    BrowserCredentialImportWarningRows(
                                        warnings: review.plan.warnings
                                    )
                                }

                                if !review.plan.rejections.isEmpty {
                                    BrowserCredentialImportRejectedRows(
                                        rejections: review.plan.rejections
                                    )
                                }

                                Label(
                                    "Passwords remain encrypted in this Space’s Keychain and never appear in logs, notifications, or diagnostics.",
                                    systemImage: "lock.shield.fill"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            .padding(CrestSpacing.extraExtraLarge)
                        }

                        Divider()
                        importFooter(review: review, space: space)
                    }
                } else {
                    ContentUnavailableView(
                        "Import No Longer Available",
                        systemImage: "key.slash",
                        description: Text(
                            "The destination Space changed. Choose the file again."
                        )
                    )
                }
            }
            .navigationTitle("Review Password Import")
            .interactiveDismissDisabled(credentials.isCommittingImport)
        }
        .browserCredentialImportReviewSizing()
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { revealedGroupIDs.removeAll() }
        }
        .onDisappear { revealedGroupIDs.removeAll() }
    }

    private func importFooter(
        review: BrowserCredentialImportReview,
        space: SpaceModel
    ) -> some View {
        HStack(spacing: CrestSpacing.medium) {
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text("Ready for \(space.settings.name)")
                    .font(.subheadline.weight(.semibold))
                Text(importSummary(review))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: CrestSpacing.medium)

            if credentials.isCommittingImport {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Importing passwords")
            }

            Button("Cancel") {
                credentials.cancelImport()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(credentials.isCommittingImport)

            Button(credentials.isCommittingImport ? "Importing…" : "Import") {
                commit()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                credentials.importReview == nil
                    || credentials.isCommittingImport
            )
        }
        .padding(.horizontal, CrestSpacing.extraExtraLarge)
        .padding(.vertical, CrestSpacing.large)
        .background(.bar)
    }

    private func importSummary(_ review: BrowserCredentialImportReview) -> String {
        guard let summary = try? review.resolvedInventory().summary else {
            return "Review the file before importing."
        }
        return
            "\(summary.acceptedCount) to import, \(summary.skippedCount) to keep or skip, \(warningLabel(summary.warningCount)), \(summary.rejectedCount) rejected."
    }

    private func warningLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 warning")
            : String(localized: "\(count) warnings")
    }

    private func commit() {
        Task { @MainActor in
            await credentials.commitImport(
                accessController: spaceAccess,
                isStillSelected: {
                    guard let review = credentials.importReview else { return false }
                    return browser.spaceModel(matching: review.destination) != nil
                }
            )
            if credentials.importReview == nil { dismiss() }
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func browserCredentialImportReviewSizing() -> some View {
        #if os(macOS)
            frame(
                minWidth: BrowserCredentialImportReviewMetrics.minimumWidth,
                idealWidth: BrowserCredentialImportReviewMetrics.idealWidth,
                minHeight: BrowserCredentialImportReviewMetrics.minimumHeight,
                idealHeight: BrowserCredentialImportReviewMetrics.idealHeight
            )
        #else
            presentationDetents([.large])
        #endif
    }
}
