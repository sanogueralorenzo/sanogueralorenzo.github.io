import SwiftUI

struct BrowserCredentialImportWarningRows: View {
    let warnings: [CredentialRowWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserCredentialImportReviewSectionHeader(
                title: "Warnings",
                detail:
                    "These credentials are valid and will be imported. Review the security limitation before continuing."
            )

            LazyVStack(spacing: 0) {
                ForEach(warnings, id: \.rowNumber) { warning in
                    BrowserCredentialImportNoticeRow(
                        rowNumber: warning.rowNumber,
                        message: String(localized: warning.caution.message),
                        tint: .orange
                    )

                    if warning.rowNumber != warnings.last?.rowNumber {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, CrestSpacing.large)
            .background(
                Color.orange.opacity(BrowserCredentialImportReviewMetrics.warningFillOpacity),
                in: RoundedRectangle(cornerRadius: CrestRadius.control))
        }
    }
}
