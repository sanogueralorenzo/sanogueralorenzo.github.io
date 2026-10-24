import SwiftUI

struct BrowserCredentialImportAccountRow: View {
    let group: CredentialImportGroup
    let selection: BrowserCredentialImportSelection
    /// The saved password the account would change, for comparison.
    let existingPassword: String?
    let revealsPasswords: Bool
    let select: (BrowserCredentialImportSelection) -> Void
    let togglePasswordVisibility: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    Text(group.origin.description)
                        .font(.headline)
                        .lineLimit(1)
                    Text(group.username.isEmpty ? "No username" : group.username)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: CrestSpacing.medium)
                HStack(spacing: CrestSpacing.small) {
                    if !group.origin.isSecure {
                        Label("HTTP", systemImage: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                    }
                    Label(status.title, systemImage: status.systemImage)
                        .foregroundStyle(status.color)
                }
                .font(.caption.weight(.medium))
            }

            if revealsPasswords {
                Divider()
                VStack(alignment: .leading, spacing: CrestSpacing.small) {
                    if let password = existingPassword {
                        BrowserCredentialImportPasswordValue(
                            label: "Current",
                            password: password
                        )
                    }
                    ForEach(
                        group.candidates.enumerated(),
                        id: \.element.rowNumber
                    ) { index, candidate in
                        BrowserCredentialImportPasswordValue(
                            label: importedPasswordLabel(
                                index: index,
                                count: group.candidates.count
                            ),
                            password: candidate.password
                        )
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Password to keep")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    selectionPicker
                        .labelsHidden()
                    passwordVisibilityButton
                }
                VStack(alignment: .leading, spacing: CrestSpacing.small) {
                    Text("Password to keep")
                        .font(.subheadline.weight(.medium))
                    selectionPicker
                        .labelsHidden()
                    passwordVisibilityButton
                }
            }

            if group.collapsedDuplicateRowCount > 0 {
                Label(
                    duplicateSummary,
                    systemImage: "doc.on.doc"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(CrestSpacing.large)
        .background(
            Color.primary.opacity(BrowserCredentialImportReviewMetrics.cardFillOpacity),
            in: RoundedRectangle(cornerRadius: CrestRadius.control)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CrestRadius.control)
                .stroke(Color.secondary.opacity(BrowserCredentialImportReviewMetrics.cardBorderOpacity))
        }
        .accessibilityElement(children: .contain)
    }

    private var status: (title: LocalizedStringKey, systemImage: String, color: Color) {
        if group.requiresChoice {
            return (
                "Needs review",
                "exclamationmark.arrow.triangle.2.circlepath",
                .orange
            )
        }
        if group.existingID != nil {
            return ("Already saved", "checkmark.circle", .secondary)
        }
        return ("New", "plus.circle.fill", .green)
    }

    private var selectionPicker: some View {
        Picker("Password to keep", selection: selectionBinding) {
            if group.existingID != nil {
                Text("Keep current password")
                    .tag(BrowserCredentialImportSelection.existing)
            }
            ForEach(
                group.candidates.enumerated(),
                id: \.element.rowNumber
            ) { index, candidate in
                Text(
                    importedPasswordChoiceLabel(
                        index: index,
                        count: group.candidates.count
                    )
                )
                .tag(
                    BrowserCredentialImportSelection.imported(
                        rowNumber: candidate.rowNumber
                    )
                )
            }
            Text("Skip this account")
                .tag(BrowserCredentialImportSelection.skip)
        }
        .pickerStyle(.menu)
    }

    private var passwordVisibilityButton: some View {
        Button(
            revealsPasswords ? "Hide Passwords" : "View Passwords",
            systemImage: revealsPasswords ? "eye.slash" : "eye",
            action: togglePasswordVisibility
        )
        .buttonStyle(.borderless)
        .accessibilityIdentifier(
            "import-password-visibility-\(group.origin.host)"
        )
    }

    private func importedPasswordChoiceLabel(index: Int, count: Int) -> String {
        count == 1
            ? String(localized: "Use imported password")
            : String(localized: "Use imported password \(index + 1)")
    }

    private func importedPasswordLabel(index: Int, count: Int) -> LocalizedStringKey {
        count == 1 ? "Imported" : "Imported \(index + 1)"
    }

    private var duplicateSummary: String {
        let count = group.collapsedDuplicateRowCount
        return count == 1
            ? String(localized: "1 identical duplicate will be skipped.")
            : String(localized: "\(count) identical duplicates will be skipped.")
    }

    private var selectionBinding: Binding<BrowserCredentialImportSelection> {
        Binding(
            get: { selection },
            set: { selection in select(selection) }
        )
    }
}
