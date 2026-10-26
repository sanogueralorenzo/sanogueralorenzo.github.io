import SwiftUI

struct BrowserCredentialImportReviewSectionHeader: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCredentialImportReviewSectionHeader(
            title: "Review Passwords", detail: "Choose which accounts to import."
        ).padding().frame(width: 380)
    }
#endif
