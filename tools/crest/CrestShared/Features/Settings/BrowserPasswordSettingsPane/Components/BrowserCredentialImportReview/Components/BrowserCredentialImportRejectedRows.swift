import SwiftUI

struct BrowserCredentialImportRejectedRows: View {
    let rejections: [CredentialRowRejection]

    private var visibleRejections: [CredentialRowRejection] {
        Array(rejections.prefix(BrowserCredentialImportReviewMetrics.maximumVisibleRejections))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserCredentialImportReviewSectionHeader(
                title: "Rejected rows",
                detail:
                    "These rows are excluded from the import. Correct the source file to import them later."
            )

            LazyVStack(spacing: 0) {
                ForEach(visibleRejections, id: \.rowNumber) { rejection in
                    BrowserCredentialImportNoticeRow(
                        rowNumber: rejection.rowNumber,
                        message: String(localized: rejection.flaw.message),
                        tint: .red
                    )

                    if rejection.rowNumber != visibleRejections.last?.rowNumber {
                        Divider()
                    }
                }

                if rejections.count > visibleRejections.count {
                    Divider()
                    Text(
                        "\(rejections.count - visibleRejections.count) additional rejected rows are included in the final count."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, CrestSpacing.medium)
                }
            }
            .padding(.horizontal, CrestSpacing.large)
            .background(
                Color.primary.opacity(BrowserCredentialImportReviewMetrics.cardFillOpacity),
                in: RoundedRectangle(cornerRadius: CrestRadius.control))
        }
    }
}
