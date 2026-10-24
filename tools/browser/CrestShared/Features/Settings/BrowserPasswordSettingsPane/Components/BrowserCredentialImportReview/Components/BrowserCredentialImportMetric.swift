import SwiftUI

struct BrowserCredentialImportMetric: View {
    let title: LocalizedStringKey
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                Text("\(value)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(CrestSpacing.medium)
        .frame(
            minWidth: BrowserCredentialImportReviewMetrics.metricMinimumWidth,
            maxWidth: .infinity,
            minHeight: BrowserCredentialImportReviewMetrics.metricMinimumHeight
        )
        .background(
            Color.primary.opacity(BrowserCredentialImportReviewMetrics.cardFillOpacity),
            in: RoundedRectangle(cornerRadius: CrestRadius.control)
        )
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("Import totals") {
        HStack {
            BrowserCredentialImportMetric(
                title: "Accounts", value: 24, systemImage: "person.crop.circle", color: .indigo)
            BrowserCredentialImportMetric(
                title: "Warnings", value: 2, systemImage: "exclamationmark.triangle", color: .orange)
        }.padding()
    }
#endif
